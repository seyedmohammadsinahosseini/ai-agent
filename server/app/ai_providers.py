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
from .models import ChatMessage
from .config import load_provider_api_key

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
    pass


def _build_system_prompt(mode: str, working_dir: Optional[str]) -> str:
    mode_prompt = BUILD_MODE_PROMPT if mode == "build" else PLAN_MODE_PROMPT
    context = f"\nThe user's selected working folder is: {working_dir}\n" if working_dir else \
              "\nNo working folder has been selected yet by the user.\n"
    return BASE_PROMPT + "\n" + mode_prompt + context


async def suggest_command(messages: list[ChatMessage], provider: str, model: Optional[str],
                           mode: str = "plan", working_dir: Optional[str] = None) -> dict:
    api_key = load_provider_api_key(provider)
    if not api_key:
        raise ProviderError(f"No API key configured for '{provider}'. Please add one in Settings.")

    system_prompt = _build_system_prompt(mode, working_dir)

    if provider == "openai":
        return await _call_openai(messages, api_key, model or "gpt-5.6-terra", system_prompt)
    elif provider == "anthropic":
        return await _call_anthropic(messages, api_key, model or "claude-sonnet-5", system_prompt)
    elif provider == "gemini":
        return await _call_gemini(messages, api_key, model or "gemini-3.5-flash", system_prompt)
    else:
        raise ProviderError(f"Unknown provider: {provider}")


def _parse_model_json(text: str) -> dict:
    cleaned = text.strip()
    if cleaned.startswith("```"):
        cleaned = cleaned.strip("`")
        if cleaned.lower().startswith("json"):
            cleaned = cleaned[4:]
    try:
        return json.loads(cleaned)
    except json.JSONDecodeError:
        return {"reply_text": text, "command": None, "explanation": None}


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
    async with httpx.AsyncClient(timeout=30) as client:
        resp = await client.post(url, json=payload, headers=headers)
        if resp.status_code != 200:
            raise ProviderError(f"OpenAI error: {resp.status_code} {resp.text[:300]}")
        data = resp.json()
        content = data["choices"][0]["message"]["content"]
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
    async with httpx.AsyncClient(timeout=30) as client:
        resp = await client.post(url, json=payload, headers=headers)
        if resp.status_code != 200:
            raise ProviderError(f"Anthropic error: {resp.status_code} {resp.text[:300]}")
        data = resp.json()
        content = data["content"][0]["text"]
        return _parse_model_json(content)


async def _call_gemini(messages: list[ChatMessage], api_key: str, model: str, system_prompt: str) -> dict:
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"
    contents = [{"role": "user" if m.role == "user" else "model", "parts": [{"text": m.content}]} for m in messages]
    payload = {
        "systemInstruction": {"parts": [{"text": system_prompt}]},
        "contents": contents,
        "generationConfig": {"temperature": 0.2, "responseMimeType": "application/json"},
    }
    async with httpx.AsyncClient(timeout=30) as client:
        resp = await client.post(url, json=payload)
        if resp.status_code != 200:
            raise ProviderError(f"Gemini error: {resp.status_code} {resp.text[:300]}")
        data = resp.json()
        content = data["candidates"][0]["content"]["parts"][0]["text"]
        return _parse_model_json(content)
