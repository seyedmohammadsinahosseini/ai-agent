"""Conservative execution policy for the selected working directory.

A shell working directory is not an operating-system sandbox. This module
therefore blocks the common ways an AI-generated command can explicitly step
outside the selected folder (absolute external paths, parent traversal,
device paths and environment-based home paths). It is defense in depth, not a
replacement for a future Windows AppContainer/VM sandbox.
"""
from __future__ import annotations

import os
import re
from dataclasses import dataclass
from pathlib import Path, PureWindowsPath
from typing import Optional


@dataclass(frozen=True)
class WorkspaceCheck:
    allowed: bool
    normalized_working_dir: Optional[str]
    message: str = ""


_PARENT_SEGMENT = re.compile(r"(?:^|[\\/\s'\"])\.\.(?:$|[\\/\s'\"])")
_WINDOWS_ABSOLUTE = re.compile(r"(?i)(?<![A-Za-z0-9_])([A-Z]:[\\/])")
_UNC_OR_DEVICE = re.compile(r"(?<![A-Za-z0-9:])(?:\\\\(?:[?.][\\/])?|//(?!/))")
_POSIX_ABSOLUTE = re.compile(r"(?<![A-Za-z0-9_.~-])/(?:etc|home|root|usr|var|tmp|opt|bin|sbin|dev|proc|sys)(?:/|\b)", re.I)
_DYNAMIC_PATH = re.compile(
    r"(?i)(%\s*(?:userprofile|home|appdata|localappdata|temp|tmp|systemroot)\s*%|"
    r"\$env:(?:userprofile|home|appdata|localappdata|temp|tmp|systemroot)\b|"
    r"\$\{?(?:home|userprofile)\}?\b|~[\\/])"
)


def _normalize(path: str | None, require_writable: bool = False) -> WorkspaceCheck:
    if not path or not path.strip():
        return WorkspaceCheck(False, None, "Select a working folder before running a command.")
    try:
        candidate = Path(path).expanduser().resolve(strict=True)
    except (OSError, RuntimeError) as exc:
        return WorkspaceCheck(False, None, f"The selected working folder is invalid: {exc}")
    if not candidate.is_dir():
        return WorkspaceCheck(False, None, "The selected working path is not a folder.")
    if not os.access(candidate, os.R_OK):
        return WorkspaceCheck(False, None, "The selected working folder is not readable.")
    if require_writable and not os.access(candidate, os.W_OK):
        return WorkspaceCheck(False, str(candidate), "Build mode requires a writable working folder.")
    return WorkspaceCheck(True, str(candidate))


def _windows_path_is_inside(command: str, marker_start: int, working_dir: str) -> bool:
    r"""Check the command text beginning at a ``C:\`` marker against cwd.

    We only need the prefix to decide whether the reference starts inside the
    workspace, so paths containing spaces do not need full shell tokenization.
    """
    cwd = str(PureWindowsPath(working_dir)).replace("/", "\\").rstrip("\\").casefold()
    tail = command[marker_start:].replace("/", "\\").casefold()
    return tail == cwd or tail.startswith(cwd + "\\") or tail.startswith(cwd + '"') or tail.startswith(cwd + "'")


def _posix_references_outside(command: str, working_dir: str) -> bool:
    cwd = working_dir.rstrip("/")
    for match in _POSIX_ABSOLUTE.finditer(command):
        tail = command[match.start():]
        if not (tail == cwd or tail.startswith(cwd + "/") or tail.startswith(cwd + '"') or tail.startswith(cwd + "'")):
            return True
    return False


def check_command_scope(command: str, working_dir: str | None,
                        require_writable: bool = False,
                        allow_multiline: bool = False) -> WorkspaceCheck:
    base = _normalize(working_dir, require_writable=require_writable)
    if not base.allowed:
        return base

    text = (command or "").strip()
    if not text:
        return WorkspaceCheck(False, base.normalized_working_dir, "An empty command cannot be executed.")

    # NUL can never be part of a legitimate process command. Multi-line
    # PowerShell scripts are useful for atomic multi-file work (for example,
    # scaffolding a small website), but only Build mode opts into them. Plan
    # mode remains restricted to one explicitly read-only command.
    if "\x00" in text:
        return WorkspaceCheck(False, base.normalized_working_dir,
                              "Commands containing NUL bytes are not allowed.")
    if ("\r" in text or "\n" in text) and not allow_multiline:
        return WorkspaceCheck(False, base.normalized_working_dir,
                              "Multi-line commands are allowed only in Build mode.")
    if _PARENT_SEGMENT.search(text):
        return WorkspaceCheck(False, base.normalized_working_dir,
                              "The command uses '..' to leave the selected working folder.")
    if _UNC_OR_DEVICE.search(text):
        return WorkspaceCheck(False, base.normalized_working_dir,
                              "UNC and device paths are outside the selected working folder.")
    if _DYNAMIC_PATH.search(text):
        return WorkspaceCheck(False, base.normalized_working_dir,
                              "Environment/home-based paths cannot be verified against the working folder.")

    for match in _WINDOWS_ABSOLUTE.finditer(text):
        if not _windows_path_is_inside(text, match.start(1), base.normalized_working_dir):
            return WorkspaceCheck(False, base.normalized_working_dir,
                                  "The command references an absolute path outside the selected working folder.")

    if _posix_references_outside(text, base.normalized_working_dir):
        return WorkspaceCheck(False, base.normalized_working_dir,
                              "The command references an absolute path outside the selected working folder.")

    return WorkspaceCheck(True, base.normalized_working_dir)
