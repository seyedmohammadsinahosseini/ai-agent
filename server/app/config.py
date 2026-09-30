"""
Configuration and secure storage for the BYOK API keys.

Security note:
- On Windows (final build), the `keyring` package should be used, which
  automatically uses the Windows Credential Manager (backed by DPAPI).
- In this PoC (running inside a Linux sandbox), if `keyring` can't find a
  suitable backend (e.g. no D-Bus/Secret Service available), it falls back to
  a locally-encrypted-ish file - for testing only. Never rely on this fallback
  as the primary mechanism in the real Windows build.
"""
import os
import json
import secrets
from pathlib import Path

APP_DIR = Path(os.environ.get("AITERM_HOME", Path.home() / ".ai-terminal"))
APP_DIR.mkdir(parents=True, exist_ok=True)

LOCAL_TOKEN_FILE = APP_DIR / "local_api_token.txt"
SECRETS_FILE = APP_DIR / "secrets.local.json"  # dev/test fallback only


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
    """Securely store the user's API key (BYOK)."""
    ok = _try_keyring_set(SERVICE_NAME, provider, api_key)
    if not ok:
        data = _fallback_load()
        data[provider] = api_key
        _fallback_save(data)


def load_provider_api_key(provider: str) -> str | None:
    val = _try_keyring_get(SERVICE_NAME, provider)
    if val:
        return val
    data = _fallback_load()
    return data.get(provider)


def list_configured_providers() -> list[str]:
    return [p for p in KNOWN_PROVIDERS if load_provider_api_key(p)]
