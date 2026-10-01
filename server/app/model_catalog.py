"""
Static catalog of models we know how to call for each provider, plus dynamic
detection: only models for providers with a saved (and presumably valid) API
key are surfaced to the client. This keeps the UI's model picker relevant to
what the user actually configured (BYOK).
"""
from .models import ModelInfo

_CATALOG: list[ModelInfo] = [
    # OpenAI
    ModelInfo(id="gpt-5.6-terra", label="GPT-5.6 Terra", provider="openai",
              description="Balanced intelligence, latency and cost. Good default."),
    ModelInfo(id="gpt-5.6-sol", label="GPT-5.6 Sol", provider="openai",
              description="Maximum reasoning depth for complex tasks."),
    ModelInfo(id="gpt-5.6-luna", label="GPT-5.6 Luna", provider="openai",
              description="Fast and cost-efficient for simple tasks."),

    # Anthropic
    ModelInfo(id="claude-sonnet-5", label="Claude Sonnet 5", provider="anthropic",
              description="Fast, general-purpose workhorse model."),
    ModelInfo(id="claude-opus-5", label="Claude Opus 5", provider="anthropic",
              description="Strongest Anthropic model for hard agentic tasks."),
    ModelInfo(id="claude-haiku-4-5", label="Claude Haiku 4.5", provider="anthropic",
              description="Fast and economical for lightweight tasks."),

    # Gemini
    ModelInfo(id="gemini-3.5-flash", label="Gemini 3.5 Flash", provider="gemini",
              description="Agentic coding and long-horizon multimodal work."),
    ModelInfo(id="gemini-3.1-pro-preview", label="Gemini 3.1 Pro", provider="gemini",
              description="Complex problem solving and precise tool use."),
    ModelInfo(id="gemini-3.5-flash-lite", label="Gemini 3.5 Flash-Lite", provider="gemini",
              description="Low-latency, high-volume tasks."),
]


def models_for_provider(provider: str) -> list[ModelInfo]:
    return [m for m in _CATALOG if m.provider == provider]


def models_for_configured_providers(configured: list[str]) -> list[ModelInfo]:
    return [m for m in _CATALOG if m.provider in configured]


def models_for_custom_providers(custom_providers: list[dict]) -> list[ModelInfo]:
    """Builds ModelInfo entries for user-added custom (arbitrary base URL)
    providers, using whatever model id(s) were auto-detected or manually
    entered when the provider was connected."""
    out: list[ModelInfo] = []
    for p in custom_providers:
        for model_id in p.get("models", []):
            out.append(ModelInfo(
                id=model_id,
                label=f"{model_id}",
                provider=f"custom:{p['id']}",
                description=f"Via {p['label']} ({p['base_url']})",
            ))
    return out


def default_model_for(provider: str) -> str:
    models = models_for_provider(provider)
    return models[0].id if models else ""
