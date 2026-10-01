"""
Configuration and secure storage for the BYOK API keys.

Security note:
- On Windows (final build), the `keyring` package should be used, which
  automatically uses the Windows Credential Manager (backed by DPAPI).
- If `keyring` cannot find a suitable backend, production fails closed rather
  than silently writing plaintext. A JSON fallback exists only when explicitly
  enabled with AITERM_ALLOW_PLAINTEXT_KEY_FALLBACK=1 for isolated development.
"""
import os
import json
import secrets
from pathlib import Path
from typing import Optional

APP_DIR = Path(os.environ.get("AITERM_HOME", Path.home() / ".ai-terminal"))
APP_DIR.mkdir(parents=True, exist_ok=True)
try:
    os.chmod(APP_DIR, 0o700)
except OSError:
    pass

LOCAL_TOKEN_FILE = APP_DIR / "local_api_token.txt"
SECRETS_FILE = APP_DIR / "secrets.local.json"  # dev/test fallback only


def _csv_env(name: str, default: str) -> list[str]:
    return [item.strip().rstrip("/") for item in os.environ.get(name, default).split(",") if item.strip()]


# Browser access is same-origin by default. Extra development origins/hosts
# must be opted into explicitly rather than inheriting a wildcard CORS policy.
ALLOWED_ORIGINS = _csv_env(
    "AITERM_ALLOWED_ORIGINS",
    "http://127.0.0.1:8765,http://localhost:8765",
)
ALLOWED_HOSTS = _csv_env("AITERM_ALLOWED_HOSTS", "127.0.0.1,localhost,testserver")
ALLOW_REMOTE_WEB_BOOTSTRAP = os.environ.get("AITERM_ALLOW_REMOTE_WEB_BOOTSTRAP", "0") == "1"
# Plaintext key storage is never silently selected. It exists only as an
# explicit development escape hatch for headless Linux environments without a
# keyring backend.
ALLOW_PLAINTEXT_SECRET_FALLBACK = os.environ.get("AITERM_ALLOW_PLAINTEXT_KEY_FALLBACK", "0") == "1"


def get_or_create_local_token() -> str:
    """
    Local token shared only between the Flutter UI and FastAPI, so no other
    unwanted process on the same machine can talk to the local API.
    """
    if LOCAL_TOKEN_FILE.exists():
        return LOCAL_TOKEN_FILE.read_text().strip()
    token = secrets.token_urlsafe(32)
    LOCAL_TOKEN_FILE.write_text(token)
    try:
        os.chmod(LOCAL_TOKEN_FILE, 0o600)
    except OSError:
        pass
    return token


def _try_keyring_set(service: str, key_name: str, value: str) -> bool:
    try:
        import keyring
        keyring.set_password(service, key_name, value)
        return True
    except Exception:
        return False


def _try_keyring_get(service: str, key_name: str) -> str | None:
    try:
        import keyring
        return keyring.get_password(service, key_name)
    except Exception:
        return None


def _fallback_load() -> dict:
    if SECRETS_FILE.exists():
        try:
            return json.loads(SECRETS_FILE.read_text())
        except (json.JSONDecodeError, OSError):
            return {}
    return {}


def _fallback_save(data: dict):
    SECRETS_FILE.write_text(json.dumps(data))
    try:
        os.chmod(SECRETS_FILE, 0o600)
    except OSError:
        pass


SERVICE_NAME = "AITerminal"
KNOWN_PROVIDERS = ["openai", "anthropic", "gemini"]


def save_provider_api_key(provider: str, api_key: str):
    """Securely store the user's API key (BYOK).

    Production fails closed when the OS credential store is unavailable. A
    plaintext JSON fallback can only be enabled explicitly for isolated local
    development with ``AITERM_ALLOW_PLAINTEXT_KEY_FALLBACK=1``.
    """
    if not api_key.strip():
        raise ValueError("API key cannot be empty.")
    if _try_keyring_set(SERVICE_NAME, provider, api_key):
        return
    if not ALLOW_PLAINTEXT_SECRET_FALLBACK:
        raise RuntimeError(
            "The operating-system credential store is unavailable, so the key was not saved. "
            "Install/configure a keyring backend; plaintext fallback is disabled."
        )
    data = _fallback_load()
    data[provider] = api_key
    _fallback_save(data)


def load_provider_api_key(provider: str) -> str | None:
    val = _try_keyring_get(SERVICE_NAME, provider)
    if val:
        return val
    if not ALLOW_PLAINTEXT_SECRET_FALLBACK:
        return None
    data = _fallback_load()
    return data.get(provider)


def list_configured_providers() -> list[str]:
    return [p for p in KNOWN_PROVIDERS if load_provider_api_key(p)]


def delete_provider_api_key(provider: str):
    """Removes a saved built-in provider key, so the user can connect a
    different key/account later without it being stuck."""
    try:
        import keyring
        keyring.delete_password(SERVICE_NAME, provider)
    except Exception:
        pass
    data = _fallback_load()
    if provider in data:
        del data[provider]
        _fallback_save(data)


# ---------------------------------------------------------------------------
# Custom (user-added, arbitrary base URL) providers.
#
# Any company/service that exposes an OpenAI-compatible /chat/completions
# endpoint (Groq, OpenRouter, Together, DeepSeek, Fireworks, local
# Ollama/LM Studio, etc.) can be added this way instead of waiting for us to
# hardcode a preset. Metadata (label/base_url/models) is stored in a small
# JSON index; each provider's actual API key is stored the same secure way
# as the built-in providers' keys (keyring, with the local-file fallback).
# ---------------------------------------------------------------------------
_CUSTOM_INDEX_KEY = "__custom_providers_index__"


def _custom_provider_key_name(provider_id: str) -> str:
    return f"custom:{provider_id}"


def _load_custom_index() -> list[dict]:
    raw = load_provider_api_key(_CUSTOM_INDEX_KEY)
    if not raw:
        return []
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return []


def _save_custom_index(index: list[dict]):
    save_provider_api_key(_CUSTOM_INDEX_KEY, json.dumps(index))


def _slugify(label: str) -> str:
    slug = "".join(c.lower() if c.isalnum() else "-" for c in label).strip("-")
    while "--" in slug:
        slug = slug.replace("--", "-")
    return slug or "provider"


def save_custom_provider(label: str, base_url: str, api_key: str,
                          models: list[str], provider_id: Optional[str] = None) -> dict:
    """Create (or update, if provider_id refers to an existing entry) a
    custom provider entry. Returns the saved metadata dict."""
    index = _load_custom_index()

    if provider_id and any(p["id"] == provider_id for p in index):
        entry_id = provider_id
    else:
        base_slug = _slugify(label)
        entry_id = base_slug
        existing_ids = {p["id"] for p in index}
        n = 2
        while entry_id in existing_ids:
            entry_id = f"{base_slug}-{n}"
            n += 1

    entry = {"id": entry_id, "label": label, "base_url": base_url.rstrip("/"), "models": models}
    index = [p for p in index if p["id"] != entry_id]
    index.append(entry)
    _save_custom_index(index)
    save_provider_api_key(_custom_provider_key_name(entry_id), api_key)
    return entry


def list_custom_providers() -> list[dict]:
    return _load_custom_index()


def get_custom_provider(provider_id: str) -> Optional[dict]:
    for p in _load_custom_index():
        if p["id"] == provider_id:
            return p
    return None


def load_custom_provider_api_key(provider_id: str) -> Optional[str]:
    return load_provider_api_key(_custom_provider_key_name(provider_id))


def delete_custom_provider(provider_id: str):
    index = [p for p in _load_custom_index() if p["id"] != provider_id]
    _save_custom_index(index)
    try:
        import keyring
        keyring.delete_password(SERVICE_NAME, _custom_provider_key_name(provider_id))
    except Exception:
        pass
    data = _fallback_load()
    if _custom_provider_key_name(provider_id) in data:
        del data[_custom_provider_key_name(provider_id)]
        _fallback_save(data)
