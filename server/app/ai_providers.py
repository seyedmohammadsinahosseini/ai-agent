"""
Shared adapter layer for multiple AI providers (BYOK: OpenAI / Anthropic / Gemini).

Goal: upstream code (main.py) doesn't need to know which service is being used;
it only talks to `suggest_command`. This makes it easy to swap providers or add
a local model (Ollama) later.

Expected model output: a natural reply + (optionally) one suggested PowerShell
command + a plain-language explanation. We ask for structured JSON in the
system prompt to make this reliable.
"""
import json
import httpx
from typing import Optional
from .models import ChatMessage, ModelInfo
from .config import load_provider_api_key, get_custom_provider, load_custom_provider_api_key
from . import model_catalog

PLAN_MODE_PROMPT = """You are an AI assistant embedded in a Windows terminal app, currently in
PLAN MODE. In this mode you have READ-ONLY access: you may look at files and discuss what you
see, but you must NEVER propose a command that modifies, deletes, moves, installs, or changes
anything on the system. If the user asks you to make a change, explain what you *would* do and
suggest they switch to Build mode to actually execute it. You may still suggest safe,
informational read-only commands (like listing a directory or reading a file) if it helps you
answer the user's question.
"""

BUILD_MODE_PROMPT = """You are an AI assistant embedded in a Windows terminal app, currently in
BUILD MODE. In this mode you are allowed to propose commands that make real changes to the
user's system (installing software, editing/deleting files, moving things around, etc.), always
within the working folder the user selected unless there's a clear, explicit reason to act
elsewhere. The application enforces its own safety checks and will ask the user to confirm
risky actions, so you don't need to add extra confirmation language yourself - just be accurate
and precise about what the command does.
"""

BASE_PROMPT = """You are a helpful AI assistant living inside a terminal application, helping a
non-technical user get things done on their Windows computer by running PowerShell commands.

Response rules:
1. Always explain what you're doing in simple, friendly language.
2. If you need to run a PowerShell/cmd command, propose exactly ONE clear, directly runnable
   command (not multiple options, not something vague).
3. Always respond with JSON in exactly this shape (no text outside the JSON):
{
  "reply_text": "friendly explanation for the user",
  "command": "the PowerShell command to run, or null if no command is needed",
  "explanation": "one simple sentence describing exactly what this command does to the user's files/system"
}
4. Never propose a command the user didn't effectively ask for (e.g. broad deletions, security
   setting changes) unless it was clearly requested.
"""


class ProviderError(Exception):
    """Raised with a message that is safe and clear to show directly to a
    non-technical end user - never a raw stack trace or an opaque HTTP
    status code on its own."""
    pass


def _http_error_message(provider_label: str, status_code: int, raw_text: str) -> str:
    """Turns a raw HTTP error from an AI provider into a plain-language
    explanation of what likely went wrong and what to do about it."""
    snippet = " ".join(raw_text.split())[:200]
    if status_code in (401, 403):
        return (
            f'{provider_label} rejected your API key (HTTP {status_code}, "Unauthorized"). '
            f"This almost always means the key is invalid, expired, or was copied from a "
            f"different provider's dashboard. Open Settings, remove the current key for "
            f"{provider_label}, and paste in a fresh one from the right provider's website."
        )
    if status_code == 404:
        return (
            f'{provider_label} couldn\'t find the requested model (HTTP 404). Either the model '
            f"id is wrong, or your API key doesn't have access to it. Try picking a different "
            f"model from the model picker on the right."
        )
    if status_code == 429:
        return (
            f"{provider_label} says you've hit a rate limit or run out of quota/credits "
            f"(HTTP 429). Check your usage and billing on {provider_label}'s website, then "
            f"try again in a moment."
        )
    if 500 <= status_code < 600:
        return (
            f"{provider_label} is having a server-side problem right now (HTTP {status_code}). "
            f"This isn't something wrong with your key or setup - try again in a minute."
        )
    return f"{provider_label} returned an unexpected error (HTTP {status_code}): {snippet}"


def _network_error_message(provider_label: str, base_url: Optional[str] = None) -> str:
    where = f" at {base_url}" if base_url else ""
    return (
        f"Couldn't reach {provider_label}{where}. Check your internet connection"
        + (", and double-check the base URL is correct" if base_url else "")
        + "."
    )


def _build_system_prompt(mode: str, working_dir: Optional[str]) -> str:
    mode_prompt = BUILD_MODE_PROMPT if mode == "build" else PLAN_MODE_PROMPT
    context = f"\nThe user's selected working folder is: {working_dir}\n" if working_dir else \
              "\nNo working folder has been selected yet by the user.\n"
    return BASE_PROMPT + "\n" + mode_prompt + context


async def suggest_command(messages: list[ChatMessage], provider: str, model: Optional[str],
                           mode: str = "plan", working_dir: Optional[str] = None) -> dict:
    system_prompt = _build_system_prompt(mode, working_dir)

    # Custom (user-added, arbitrary base URL) provider: "custom:<slug>".
    if provider.startswith("custom:"):
        custom_id = provider[len("custom:"):]
        cfg = get_custom_provider(custom_id)
        if not cfg:
            raise ProviderError(f"Custom provider '{custom_id}' is not configured.")
        api_key = load_custom_provider_api_key(custom_id)
        if not api_key:
            raise ProviderError(f"No API key stored for custom provider '{cfg['label']}'.")
        chosen_model = model or (cfg["models"][0] if cfg.get("models") else None)
        if not chosen_model:
            raise ProviderError(
                f"No model configured for custom provider '{cfg['label']}'. "
                "Add one when connecting the provider in Settings."
            )
        return await _call_openai_compatible(messages, api_key, chosen_model, system_prompt,
                                              cfg["base_url"], provider_label=cfg["label"])

    api_key = load_provider_api_key(provider)
    if not api_key:
        raise ProviderError(f"No API key configured for '{provider}'. Please add one in Settings.")

    if provider == "openai":
        return await _call_openai(messages, api_key, model or "gpt-5.6-terra", system_prompt)
    elif provider == "anthropic":
        return await _call_anthropic(messages, api_key, model or "claude-sonnet-5", system_prompt)
    elif provider == "gemini":
        return await _call_gemini(messages, api_key, model or "gemini-3.5-flash", system_prompt)
    else:
        raise ProviderError(f"Unknown provider: {provider}")


def _parse_model_json(text) -> dict:
    if not isinstance(text, str) or not text.strip():
        return {
            "reply_text": (
                "The model responded, but didn't return any readable text (it may have "
                "returned an empty or tool/function-call-only response). Try rephrasing "
                "your request, or try again."
            ),
            "command": None,
            "explanation": None,
        }
    cleaned = text.strip()
    if cleaned.startswith("```"):
        cleaned = cleaned.strip("`")
        if cleaned.lower().startswith("json"):
            cleaned = cleaned[4:]
    try:
        return json.loads(cleaned)
    except json.JSONDecodeError:
        return {"reply_text": text, "command": None, "explanation": None}



def _extract_chat_message_content(data: dict, provider_label: str) -> Optional[str]:
    """Pulls the text content out of an OpenAI-shaped chat-completions
    response, returning None (instead of crashing) if the model didn't
    return plain text - e.g. because it made a tool/function call instead,
    refused to answer, or was cut off by a content filter."""
    try:
        choice = data["choices"][0]
        message = choice.get("message", {}) or {}
    except (KeyError, IndexError, TypeError):
        return None
    content = message.get("content")
    if content:
        return content
    if message.get("refusal"):
        return f"{provider_label} declined to answer: {message['refusal']}"
    if message.get("tool_calls"):
        return (
            f"{provider_label} tried to call a tool/function instead of replying with text, "
            f"which this app doesn't support yet. Try rephrasing your request as a direct "
            f"question or instruction."
        )
    finish_reason = choice.get("finish_reason")
    if finish_reason == "content_filter":
        return f"{provider_label} blocked this response due to its content filter."
    return None


async def _call_openai(messages: list[ChatMessage], api_key: str, model: str, system_prompt: str) -> dict:
    url = "https://api.openai.com/v1/chat/completions"
    payload = {
        "model": model,
        "messages": [{"role": "system", "content": system_prompt}] +
                    [{"role": m.role, "content": m.content} for m in messages],
        "response_format": {"type": "json_object"},
        "temperature": 0.2,
    }
    headers = {"Authorization": f"Bearer {api_key}"}
    try:
        async with httpx.AsyncClient(timeout=30) as client:
            resp = await client.post(url, json=payload, headers=headers)
    except httpx.RequestError:
        raise ProviderError(_network_error_message("OpenAI"))
    if resp.status_code != 200:
        raise ProviderError(_http_error_message("OpenAI", resp.status_code, resp.text))
    data = resp.json()
    content = _extract_chat_message_content(data, "OpenAI")
    return _parse_model_json(content)


async def _call_anthropic(messages: list[ChatMessage], api_key: str, model: str, system_prompt: str) -> dict:
    url = "https://api.anthropic.com/v1/messages"
    payload = {
        "model": model,
        "max_tokens": 1024,
        "system": system_prompt,
        "messages": [{"role": m.role if m.role != "system" else "user", "content": m.content} for m in messages],
    }
    headers = {
        "x-api-key": api_key,
        "anthropic-version": "2023-06-01",
    }
    try:
        async with httpx.AsyncClient(timeout=30) as client:
            resp = await client.post(url, json=payload, headers=headers)
    except httpx.RequestError:
        raise ProviderError(_network_error_message("Anthropic"))
    if resp.status_code != 200:
        raise ProviderError(_http_error_message("Anthropic", resp.status_code, resp.text))
    data = resp.json()
    content = None
    blocks = data.get("content") or []
    for block in blocks:
        if isinstance(block, dict) and block.get("type") == "text" and block.get("text"):
            content = block["text"]
            break
    if content is None and data.get("stop_reason") == "refusal":
        content = "Anthropic declined to answer this request."
    return _parse_model_json(content)


async def _call_openai_compatible(messages: list[ChatMessage], api_key: str, model: str,
                                   system_prompt: str, base_url: str, provider_label: str = "This provider") -> dict:
    """Calls any third-party provider that speaks the OpenAI chat-completions
    API shape (Groq, OpenRouter, Together, DeepSeek, Fireworks, local
    Ollama/LM Studio in OpenAI-compat mode, etc.). `base_url` is expected to
    be the API root up to and including '/v1' (e.g.
    'https://openrouter.ai/api/v1'), matching the convention used by the
    official OpenAI SDKs' `base_url` parameter.

    We deliberately don't force `response_format: json_object` here since
    not all third-party providers support that field - `_parse_model_json`
    already degrades gracefully to a plain-text reply if the model doesn't
    return valid JSON.
    """
    url = f"{base_url.rstrip('/')}/chat/completions"
    payload = {
        "model": model,
        "messages": [{"role": "system", "content": system_prompt}] +
                    [{"role": m.role, "content": m.content} for m in messages],
        "temperature": 0.2,
    }
    headers = {"Authorization": f"Bearer {api_key}"}
    try:
        async with httpx.AsyncClient(timeout=30) as client:
            resp = await client.post(url, json=payload, headers=headers)
    except httpx.RequestError:
        raise ProviderError(_network_error_message(provider_label, base_url))
    if resp.status_code != 200:
        raise ProviderError(_http_error_message(provider_label, resp.status_code, resp.text))
    try:
        data = resp.json()
    except ValueError:
        raise ProviderError(
            f"{provider_label} responded, but not in the format we expected from an "
            f"OpenAI-compatible API. It may not actually support the chat completions "
            f"endpoint at this base URL."
        )
    if "choices" not in data:
        raise ProviderError(
            f"{provider_label} responded, but not in the format we expected from an "
            f"OpenAI-compatible API. It may not actually support the chat completions "
            f"endpoint at this base URL."
        )
    content = _extract_chat_message_content(data, provider_label)
    return _parse_model_json(content)


async def discover_openai_models(api_key: str) -> list[str]:
    """Live list of models this OpenAI key can actually access, instead of a
    hardcoded guess that can silently go stale as OpenAI retires/renames
    models. Falls back to an empty list (caller should fall back to the
    static catalog) on any failure."""
    url = "https://api.openai.com/v1/models"
    headers = {"Authorization": f"Bearer {api_key}"}
    try:
        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.get(url, headers=headers)
            if resp.status_code != 200:
                return []
            data = resp.json()
    except Exception:
        return []
    ids = [item.get("id") for item in data.get("data", []) if isinstance(item, dict) and item.get("id")]
    # Keep chat-capable text models; drop embeddings/audio/image/moderation/
    # legacy-completion models that would never be useful here and that a
    # chat-completions call against would just 400/404 anyway.
    excluded_markers = (
        "embedding", "whisper", "tts", "dall-e", "moderation", "davinci",
        "babbage", "ada", "curie", "audio", "image", "realtime",
        "transcribe", "search", "computer-use", "sora",
    )
    chat_ids = [i for i in ids if not any(m in i for m in excluded_markers)]
    return sorted(chat_ids, reverse=True)


async def discover_anthropic_models(api_key: str) -> list[str]:
    """Live list of models this Anthropic key can access (Anthropic has
    supported GET /v1/models for this since 2024)."""
    url = "https://api.anthropic.com/v1/models"
    headers = {"x-api-key": api_key, "anthropic-version": "2023-06-01"}
    try:
        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.get(url, headers=headers)
            if resp.status_code != 200:
                return []
            data = resp.json()
    except Exception:
        return []
    ids = [item.get("id") for item in data.get("data", []) if isinstance(item, dict) and item.get("id")]
    return sorted(ids, reverse=True)


async def discover_gemini_models(api_key: str) -> list[str]:
    """Live list of Gemini models this key can access that support
    generateContent (i.e. are usable for chat), instead of a hardcoded
    model id that can go stale as Google retires/renames models."""
    url = f"https://generativelanguage.googleapis.com/v1beta/models?key={api_key}"
    try:
        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.get(url)
            if resp.status_code != 200:
                return []
            data = resp.json()
    except Exception:
        return []
    out = []
    for m in data.get("models", []):
        name = m.get("name", "")
        methods = m.get("supportedGenerationMethods", [])
        if "generateContent" in methods and name.startswith("models/"):
            out.append(name[len("models/"):])
    return sorted(out, reverse=True)


_DISCOVER_FN = {
    "openai": discover_openai_models,
    "anthropic": discover_anthropic_models,
    "gemini": discover_gemini_models,
}


async def live_models_for_builtin_provider(provider: str, api_key: str) -> list[ModelInfo]:
    """Returns the models this specific API key can actually use for
    `provider`, discovered live from the provider's own API. Falls back to
    our best-guess static catalog only if live discovery fails (e.g. no
    internet right now) so the picker never ends up completely empty.

    This is what prevents "model not found" (HTTP 404) errors caused by a
    hardcoded model id that has since been renamed/retired by the provider,
    or that this particular account/tier doesn't have access to.
    """
    discover_fn = _DISCOVER_FN.get(provider)
    live_ids = await discover_fn(api_key) if discover_fn else []
    if not live_ids:
        return model_catalog.models_for_provider(provider)

    static_by_id = {m.id: m for m in model_catalog.models_for_provider(provider)}
    out = []
    for model_id in live_ids:
        if model_id in static_by_id:
            out.append(static_by_id[model_id])
        else:
            out.append(ModelInfo(id=model_id, label=model_id, provider=provider,
                                  description="Detected from your API key"))
    return out


async def discover_models(base_url: str, api_key: str) -> list[str]:
    """Best-effort auto-detection of which models an OpenAI-compatible key
    can access, by calling the standard GET {base_url}/models endpoint. If
    the provider doesn't support this (or the call fails for any reason),
    returns an empty list and the caller should fall back to a
    manually-entered model id.
    """
    url = f"{base_url.rstrip('/')}/models"
    headers = {"Authorization": f"Bearer {api_key}"}
    try:
        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.get(url, headers=headers)
            if resp.status_code != 200:
                return []
            data = resp.json()
            items = data.get("data", data if isinstance(data, list) else [])
            ids = [item.get("id") for item in items if isinstance(item, dict) and item.get("id")]
            return sorted(ids)
    except Exception:
        return []


async def _call_gemini(messages: list[ChatMessage], api_key: str, model: str, system_prompt: str) -> dict:
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"
    contents = [{"role": "user" if m.role == "user" else "model", "parts": [{"text": m.content}]} for m in messages]
    payload = {
        "systemInstruction": {"parts": [{"text": system_prompt}]},
        "contents": contents,
        "generationConfig": {"temperature": 0.2, "responseMimeType": "application/json"},
    }
    try:
        async with httpx.AsyncClient(timeout=30) as client:
            resp = await client.post(url, json=payload)
    except httpx.RequestError:
        raise ProviderError(_network_error_message("Gemini"))
    if resp.status_code != 200:
        raise ProviderError(_http_error_message("Gemini", resp.status_code, resp.text))
    data = resp.json()
    content = None
    candidates = data.get("candidates") or []
    if candidates:
        candidate = candidates[0]
        parts = (candidate.get("content") or {}).get("parts") or []
        for part in parts:
            if isinstance(part, dict) and part.get("text"):
                content = part["text"]
                break
        if content is None and candidate.get("finishReason") == "SAFETY":
            content = "Gemini blocked this response due to its safety filter."
    if content is None and data.get("promptFeedback", {}).get("blockReason"):
        content = f"Gemini blocked this request: {data['promptFeedback']['blockReason']}."
    return _parse_model_json(content)
