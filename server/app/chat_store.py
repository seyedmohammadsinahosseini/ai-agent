"""
Local persistent chat history (the left sidebar's "New Chat" + past
conversations list).

Stored as a small SQLite database next to the other local app state (same
directory as the BYOK keys' JSON fallback and the local auth token - see
config.py's APP_DIR), using Python's built-in `sqlite3` module so this adds
no extra dependency. Everything here is local-only: there is no cloud sync,
matching the rest of the app's "your machine, your data" design.
"""
import json
import sqlite3
import uuid
from datetime import datetime, timezone
from typing import Optional

from .config import APP_DIR

DB_PATH = APP_DIR / "chats.db"

# Columns on the `messages` table that hold rich assistant-turn metadata
# (so a reopened chat can redraw a suggested command / risk badge / output
# the same way it looked live) are kept in one JSON blob rather than one
# column per field, so adding new fields later doesn't need a migration.
_EXTRA_FIELDS = (
    "mode", "suggested_command", "risk_level", "risk_human_reason",
    "auto_executed", "execution_output", "execution_exit_code", "blocked_reason",
)


def _connect() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def _init_db():
    conn = _connect()
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS chats (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
        """
    )
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS messages (
            id TEXT PRIMARY KEY,
            chat_id TEXT NOT NULL,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            is_error INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            extra_json TEXT
        )
        """
    )
    conn.execute("CREATE INDEX IF NOT EXISTS idx_messages_chat_id ON messages(chat_id)")
    conn.commit()
    conn.close()


_init_db()


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def auto_title_from_text(text: str, max_len: int = 48) -> str:
    """Derives a short, human-readable chat title from the first user
    message, the same way ChatGPT/most chat apps title new conversations."""
    cleaned = " ".join((text or "").split())
    if not cleaned:
        return "New chat"
    if len(cleaned) <= max_len:
        return cleaned
    return cleaned[: max_len].rstrip() + "..."


def create_chat(title: str = "New chat") -> dict:
    chat_id = str(uuid.uuid4())
    now = _now()
    conn = _connect()
    conn.execute(
        "INSERT INTO chats (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)",
        (chat_id, title, now, now),
    )
    conn.commit()
    conn.close()
    return {"id": chat_id, "title": title, "created_at": now, "updated_at": now, "message_count": 0}


def list_chats() -> list[dict]:
    conn = _connect()
    rows = conn.execute(
        """
        SELECT c.id, c.title, c.created_at, c.updated_at,
               (SELECT COUNT(*) FROM messages m WHERE m.chat_id = c.id) AS message_count
        FROM chats c
        ORDER BY c.updated_at DESC
        """
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def chat_exists(chat_id: str) -> bool:
    conn = _connect()
    row = conn.execute("SELECT 1 FROM chats WHERE id = ?", (chat_id,)).fetchone()
    conn.close()
    return row is not None


def get_chat(chat_id: str) -> Optional[dict]:
    conn = _connect()
    chat_row = conn.execute("SELECT * FROM chats WHERE id = ?", (chat_id,)).fetchone()
    if not chat_row:
        conn.close()
        return None
    msg_rows = conn.execute(
        "SELECT * FROM messages WHERE chat_id = ? ORDER BY created_at ASC, rowid ASC",
        (chat_id,),
    ).fetchall()
    conn.close()

    messages = []
    for r in msg_rows:
        extra = json.loads(r["extra_json"]) if r["extra_json"] else {}
        msg = {
            "id": r["id"],
            "role": r["role"],
            "content": r["content"],
            "is_error": bool(r["is_error"]),
            "created_at": r["created_at"],
        }
        for field in _EXTRA_FIELDS:
            if field in extra:
                msg[field] = extra[field]
        messages.append(msg)

    return {
        "id": chat_row["id"],
        "title": chat_row["title"],
        "created_at": chat_row["created_at"],
        "updated_at": chat_row["updated_at"],
        "messages": messages,
    }


def add_message(chat_id: str, role: str, content: str, is_error: bool = False,
                 extra: Optional[dict] = None) -> dict:
    msg_id = str(uuid.uuid4())
    now = _now()
    extra_json = json.dumps({k: v for k, v in (extra or {}).items() if v is not None}) if extra else None
    conn = _connect()
    conn.execute(
        "INSERT INTO messages (id, chat_id, role, content, is_error, created_at, extra_json) "
        "VALUES (?, ?, ?, ?, ?, ?, ?)",
        (msg_id, chat_id, role, content, int(is_error), now, extra_json),
    )
    conn.execute("UPDATE chats SET updated_at = ? WHERE id = ?", (now, chat_id))
    conn.commit()
    conn.close()
    return {"id": msg_id, "role": role, "content": content, "is_error": is_error, "created_at": now}


def rename_chat(chat_id: str, title: str):
    conn = _connect()
    conn.execute("UPDATE chats SET title = ? WHERE id = ?", (title.strip() or "New chat", chat_id))
    conn.commit()
    conn.close()


def delete_chat(chat_id: str):
    conn = _connect()
    conn.execute("DELETE FROM messages WHERE chat_id = ?", (chat_id,))
    conn.execute("DELETE FROM chats WHERE id = ?", (chat_id,))
    conn.commit()
    conn.close()
