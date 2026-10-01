"""
File upload handling.

Two upload kinds:
- "context": file is stored in a local scratch area purely so its content/text
  can be shared with the AI model as conversation context. Never touches the
  user's selected working directory.
- "workspace": file is copied directly into the currently selected working
  directory, so the agent can act on it (e.g. "summarize this document",
  "refactor this script"). Requires a working_dir to be selected first.

Security notes:
- Filenames are sanitized (no path traversal) before ever touching disk.
- Uploaded file size is capped to avoid trivial resource-exhaustion.
- Context uploads never leave the app's private storage directory; only their
  extracted text (bounded in size) is included in prompts sent to the AI.
"""
import os
import re
import time
import uuid
from pathlib import Path
from dataclasses import dataclass

from .config import APP_DIR

CONTEXT_STORE_DIR = APP_DIR / "uploads"
CONTEXT_STORE_DIR.mkdir(parents=True, exist_ok=True)

MAX_UPLOAD_BYTES = 25 * 1024 * 1024  # 25 MB
MAX_CONTEXT_CHARS = 20_000  # bound how much of a context file we inline into prompts

_SAFE_NAME_RE = re.compile(r"[^A-Za-z0-9_.\-]+")


@dataclass
class StoredUpload:
    id: str
    filename: str
    kind: str
    size_bytes: int
    saved_path: str


def sanitize_filename(filename: str) -> str:
    # Treat both slash styles as path separators on every host. Otherwise a
    # Windows traversal-style name is handled differently by pathlib on POSIX,
    # making sanitization and its tests platform-dependent.
    basename = filename.replace("\\", "/").rsplit("/", 1)[-1]
    name = _SAFE_NAME_RE.sub("_", basename) or "file"
    name = name.rstrip(". ") or "file"
    windows_reserved = {"CON", "PRN", "AUX", "NUL", *(f"COM{i}" for i in range(1, 10)),
                        *(f"LPT{i}" for i in range(1, 10))}
    if Path(name).stem.upper() in windows_reserved or name in (".", ".."):
        name = f"_{name.replace('.', '_')}"
    # Stay below common filesystem component limits while preserving a useful
    # extension and leaving room for collision suffixes/UUID prefixes.
    if len(name) > 180:
        suffix = Path(name).suffix[:20]
        stem_limit = max(1, 180 - len(suffix))
        name = Path(name).stem[:stem_limit] + suffix
    return name


_UPLOAD_REGISTRY: dict[str, StoredUpload] = {}


def save_context_upload(filename: str, data: bytes) -> StoredUpload:
    if len(data) > MAX_UPLOAD_BYTES:
        raise ValueError(f"File too large (max {MAX_UPLOAD_BYTES // (1024*1024)} MB).")
    safe_name = sanitize_filename(filename)
    upload_id = uuid.uuid4().hex
    dest = CONTEXT_STORE_DIR / f"{upload_id}__{safe_name}"
    dest.write_bytes(data)
    upload = StoredUpload(id=upload_id, filename=safe_name, kind="context",
                           size_bytes=len(data), saved_path=str(dest))
    _UPLOAD_REGISTRY[upload_id] = upload
    return upload


def save_workspace_upload(filename: str, data: bytes, working_dir: str) -> StoredUpload:
    if len(data) > MAX_UPLOAD_BYTES:
        raise ValueError(f"File too large (max {MAX_UPLOAD_BYTES // (1024*1024)} MB).")
    try:
        target_dir = Path(working_dir).expanduser().resolve(strict=True)
    except (OSError, RuntimeError):
        raise ValueError("The selected working folder is not valid.")
    if not target_dir.is_dir():
        raise ValueError("The selected working folder is not valid.")
    if not os.access(target_dir, os.W_OK):
        raise ValueError("The selected working folder is not writable.")

    safe_name = sanitize_filename(filename)
    dest = target_dir / safe_name
    # Avoid overwriting existing files silently
    counter = 1
    stem, suffix = Path(safe_name).stem, Path(safe_name).suffix
    while dest.exists():
        dest = target_dir / f"{stem}_{counter}{suffix}"
        counter += 1

    dest.write_bytes(data)
    upload_id = uuid.uuid4().hex
    upload = StoredUpload(id=upload_id, filename=dest.name, kind="workspace",
                           size_bytes=len(data), saved_path=str(dest))
    _UPLOAD_REGISTRY[upload_id] = upload
    return upload


def get_upload(upload_id: str) -> StoredUpload | None:
    return _UPLOAD_REGISTRY.get(upload_id)


def delete_context_upload(upload_id: str) -> bool:
    upload = _UPLOAD_REGISTRY.get(upload_id)
    if not upload or upload.kind != "context":
        return False
    _UPLOAD_REGISTRY.pop(upload_id, None)
    try:
        Path(upload.saved_path).unlink(missing_ok=True)
    except OSError:
        return False
    return True


def read_context_text(upload_id: str) -> str | None:
    """Best-effort bounded text extraction for inlining into the AI prompt."""
    upload = _UPLOAD_REGISTRY.get(upload_id)
    if not upload or upload.kind != "context":
        return None
    try:
        content = Path(upload.saved_path).read_text(errors="ignore")
    except (UnicodeDecodeError, OSError):
        return "[binary file - content not shown]"
    if len(content) > MAX_CONTEXT_CHARS:
        content = content[:MAX_CONTEXT_CHARS] + "\n...[truncated]"
    return content


def cleanup_stale_context_files(max_age_seconds: int = 24 * 60 * 60) -> int:
    """Remove scratch files left behind by crashes or abandoned browser tabs."""
    cutoff = time.time() - max_age_seconds
    removed = 0
    for path in CONTEXT_STORE_DIR.iterdir():
        try:
            if path.is_file() and path.stat().st_mtime < cutoff:
                path.unlink()
                removed += 1
        except OSError:
            continue
    return removed


cleanup_stale_context_files()
