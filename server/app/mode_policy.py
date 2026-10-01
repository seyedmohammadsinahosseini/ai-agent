"""Strict Plan-mode read-only enforcement.

Plan mode uses an allowlist, rejects shell composition/redirection and only
accepts commands whose *entire* command name is known to be observational.
This deliberately prefers a false rejection over accidentally writing data.
"""
from __future__ import annotations

import re

# Shell composition, output/input redirection, command substitution and
# multiple lines can turn an otherwise read-only prefix into a write/execute.
_FORBIDDEN_SYNTAX = re.compile(r"[\r\n;&|<>`(){}]|\$env:|%[^%\r\n]+%|(?:^|\s)~[\\/]", re.I)

# Commands whose arguments cannot turn them into a state-changing operation
# under normal PowerShell/cmd/POSIX semantics. Commands with mixed read/write
# behavior (echo, date, time, find, git, PowerShell language expressions) are
# intentionally absent.
_READ_ONLY_COMMANDS = {
    "ls", "dir", "cat", "type", "more", "pwd", "tree",
    "whoami", "hostname", "where", "which", "where.exe",
    "grep", "findstr", "wc", "head", "tail", "du", "df",
    "ping", "tracert", "traceroute", "nslookup",
    "get-childitem", "get-content", "get-item", "get-process",
    "get-service", "get-location", "get-date", "get-command",
    "get-filehash", "test-path", "select-string", "measure-object",
}

# A handful of version/help queries are useful but the base executable is not
# generally read-only, so match the full shape instead of allowlisting it.
_SAFE_FULL_PATTERNS = [
    re.compile(r"^(?:python|python3|node|npm|pip|pip3|git|cmake|flutter|dart)\s+(?:--version|version)\s*$", re.I),
    re.compile(r"^git\s+(?:status|log|show|diff)(?:\s+[^\r\n;&|<>`]*)?$", re.I),
    re.compile(r"^(?:date|time)\s+/t\s*$", re.I),
]


def _unwrap_simple_powershell(command: str) -> str | None:
    """Accept a simple PowerShell wrapper used by older model prompts.

    Encoded commands and complicated quoting are rejected. The native Windows
    engine now launches PowerShell directly, so this is mainly compatibility.
    """
    match = re.fullmatch(
        r"powershell(?:\.exe)?\s+(?:-NoLogo\s+)?(?:-NoProfile\s+)?(?:-NonInteractive\s+)?"
        r"-Command\s+(.+)",
        command,
        flags=re.I,
    )
    if not match:
        return None
    inner = match.group(1).strip()
    if len(inner) >= 2 and inner[0] == inner[-1] and inner[0] in ("'", '"'):
        inner = inner[1:-1].strip()
    if not inner or "-encodedcommand" in inner.lower():
        return None
    return inner


def is_read_only_command(command: str) -> bool:
    normalized = (command or "").strip()
    if not normalized or _FORBIDDEN_SYNTAX.search(normalized):
        return False

    wrapped = _unwrap_simple_powershell(normalized)
    if wrapped is not None:
        return is_read_only_command(wrapped)

    if any(pattern.fullmatch(normalized) for pattern in _SAFE_FULL_PATTERNS):
        return True

    match = re.match(r"^([A-Za-z][A-Za-z0-9_.-]*)\b", normalized)
    return bool(match and match.group(1).lower() in _READ_ONLY_COMMANDS)


def plan_mode_allows(command: str) -> tuple[bool, str]:
    if is_read_only_command(command):
        return True, ""
    return False, (
        "Plan mode only runs a single, explicitly read-only command. "
        "Redirection, pipelines, command chaining, substitutions and any unknown command are blocked; "
        "switch to Build mode for changes."
    )
