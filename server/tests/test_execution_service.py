import importlib
import sys
import types
from pathlib import Path

import app as app_package


class _Classification:
    def __init__(self, level: str):
        self.level = level
        self.human_reason = f"classified {level.lower()}"


def _service_with_level(monkeypatch, level: str):
    fake = types.ModuleType("app.engine_bridge")
    fake.classify_command = lambda _command: _Classification(level)
    fake.risk_level_name = lambda value: value

    # Install the fake before importing execution_service. Unit policy tests
    # must not require the separately compiled native extension to exist.
    monkeypatch.setitem(sys.modules, "app.engine_bridge", fake)
    monkeypatch.setattr(app_package, "engine_bridge", fake, raising=False)
    monkeypatch.delitem(sys.modules, "app.execution_service", raising=False)
    return importlib.import_module("app.execution_service")


def test_plan_mode_blocks_write_before_native_classifier(tmp_path: Path, monkeypatch):
    service = _service_with_level(monkeypatch, "SAFE")
    result = service.authorize(
        "echo changed > file.txt", "plan", False, None, str(tmp_path)
    )
    assert not result.allowed
    assert result.risk_level == "BLOCKED_BY_MODE"


def test_workspace_escape_is_blocked(tmp_path: Path, monkeypatch):
    service = _service_with_level(monkeypatch, "SAFE")
    result = service.authorize(
        "Get-Content ../secret.txt", "plan", False, None, str(tmp_path)
    )
    assert not result.allowed
    assert result.risk_level == "BLOCKED_BY_WORKSPACE"


def test_unknown_command_requires_confirmation(tmp_path: Path, monkeypatch):
    service = _service_with_level(monkeypatch, "CONFIRM")
    first = service.authorize("custom-tool", "build", False, None, str(tmp_path))
    assert not first.allowed
    assert first.risk_level == "CONFIRM"

    confirmed = service.authorize("custom-tool", "build", True, None, str(tmp_path))
    assert confirmed.allowed
    assert confirmed.normalized_working_dir == str(tmp_path.resolve())


def test_build_mode_allows_confirmed_multiline_script(tmp_path: Path, monkeypatch):
    service = _service_with_level(monkeypatch, "CONFIRM")
    script = "Set-Content index.html '<h1>Hello</h1>'\nSet-Content app.js 'ready'"

    waiting = service.authorize(script, "build", False, None, str(tmp_path))
    assert not waiting.allowed
    assert waiting.risk_level == "CONFIRM"

    confirmed = service.authorize(script, "build", True, None, str(tmp_path))
    assert confirmed.allowed


def test_dangerous_command_requires_exact_phrase(tmp_path: Path, monkeypatch):
    service = _service_with_level(monkeypatch, "DANGEROUS")
    wrong = service.authorize("danger-tool", "build", True, "yes", str(tmp_path))
    assert not wrong.allowed
    ok = service.authorize(
        "danger-tool", "build", True, service.DANGEROUS_CONFIRMATION_PHRASE, str(tmp_path)
    )
    assert ok.allowed
