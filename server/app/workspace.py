"""
Working-directory selection and browsing.

Security notes:
- The folder picker only ever lists real directories on disk; it never lets the
  client pass an arbitrary path straight into command execution without
  validation (`resolve_working_dir` normalizes + checks existence).
- In Plan mode, the agent is only ever allowed to READ within the working
  directory (see main.py enforcement) - this module itself is agnostic to mode,
  it just answers "does this path exist and is it a directory".
"""
import os
from pathlib import Path
from .models import FolderEntry, BrowseFolderResponse


def _safe_listdir(path: Path) -> list[FolderEntry]:
    entries = []
    try:
        for child in sorted(path.iterdir(), key=lambda p: (not p.is_dir(), p.name.lower())):
            try:
                is_dir = child.is_dir()
            except OSError:
                continue
            # Skip hidden/system noise for a cleaner picker UI
            if child.name.startswith('.') and child.name not in ('.',):
                continue
            entries.append(FolderEntry(name=child.name, path=str(child), is_dir=is_dir))
    except PermissionError:
        pass
    return entries


def browse(path: str | None) -> BrowseFolderResponse:
    base = Path(path) if path else Path.home()
    try:
        base = base.resolve()
    except OSError:
        base = Path.home().resolve()

    if not base.exists() or not base.is_dir():
        base = Path.home().resolve()

    parent = str(base.parent) if base.parent != base else None
    entries = [e for e in _safe_listdir(base) if e.is_dir]

    return BrowseFolderResponse(current_path=str(base), parent_path=parent, entries=entries)


def resolve_working_dir(path: str) -> tuple[bool, str]:
    """Validate a working directory path. Returns (ok, normalized_path_or_error)."""
    try:
        p = Path(path).expanduser().resolve()
    except OSError as e:
        return False, f"Invalid path: {e}"

    if not p.exists():
        return False, "This folder does not exist."
    if not p.is_dir():
        return False, "The selected path is not a folder."
    if not os.access(p, os.R_OK):
        return False, "This folder is not readable by the application."

    return True, str(p)
