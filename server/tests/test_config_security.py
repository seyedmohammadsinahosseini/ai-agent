import pytest

from app import config


def test_secret_storage_fails_closed_without_keyring(monkeypatch):
    monkeypatch.setattr(config, "_try_keyring_set", lambda *_args: False)
    monkeypatch.setattr(config, "ALLOW_PLAINTEXT_SECRET_FALLBACK", False)
    with pytest.raises(RuntimeError, match="credential store is unavailable"):
        config.save_provider_api_key("openai", "test-key")


def test_empty_key_is_rejected(monkeypatch):
    monkeypatch.setattr(config, "_try_keyring_set", lambda *_args: True)
    with pytest.raises(ValueError, match="cannot be empty"):
        config.save_provider_api_key("openai", "   ")
