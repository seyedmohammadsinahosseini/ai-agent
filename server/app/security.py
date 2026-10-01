"""Security helpers for the local HTTP/WebSocket boundary.

The app is intentionally local-only. These helpers make that assumption
explicit instead of relying on permissive CORS plus a bearer token that a
cross-origin web page could obtain.
"""
from __future__ import annotations

import ipaddress
import secrets
import threading
import time
from dataclasses import dataclass
from urllib.parse import urlparse


def is_loopback_address(address: str | None) -> bool:
    if not address:
        return False
    if address.lower() == "localhost":
        return True
    try:
        return ipaddress.ip_address(address).is_loopback
    except ValueError:
        return False


def origin_is_allowed(origin: str | None, host_header: str | None,
                      allowed_origins: list[str]) -> bool:
    """Accept native clients (no Origin), configured origins, and same-origin
    browser clients. Comparing against Host keeps proxied same-origin builds
    working while rejecting an arbitrary website talking to localhost.
    """
    if not origin:
        return True
    normalized = origin.rstrip("/")
    if normalized in {item.rstrip("/") for item in allowed_origins}:
        return True
    try:
        parsed = urlparse(normalized)
    except ValueError:
        return False
    return bool(parsed.scheme in ("http", "https") and parsed.netloc and
                host_header and parsed.netloc.lower() == host_header.lower())


@dataclass(frozen=True)
class _Ticket:
    expires_at: float


class WebSocketTicketStore:
    """Issues short-lived, one-use WebSocket tickets.

    Browsers cannot reliably attach an Authorization header to a WebSocket
    handshake. A ticket keeps the long-lived local API token out of URLs and
    access logs while still authenticating the socket.
    """

    def __init__(self, ttl_seconds: int = 30, max_pending: int = 256):
        self._ttl_seconds = ttl_seconds
        self._max_pending = max_pending
        self._tickets: dict[str, _Ticket] = {}
        self._lock = threading.Lock()

    def issue(self) -> str:
        now = time.monotonic()
        ticket = secrets.token_urlsafe(32)
        with self._lock:
            self._purge_locked(now)
            if len(self._tickets) >= self._max_pending:
                # Drop the oldest ticket. This is a local single-user app, so
                # reaching this limit indicates stale/abusive requests.
                oldest = min(self._tickets, key=lambda key: self._tickets[key].expires_at)
                self._tickets.pop(oldest, None)
            self._tickets[ticket] = _Ticket(now + self._ttl_seconds)
        return ticket

    def consume(self, ticket: str | None) -> bool:
        if not ticket:
            return False
        now = time.monotonic()
        with self._lock:
            self._purge_locked(now)
            entry = self._tickets.pop(ticket, None)
            return entry is not None and entry.expires_at > now

    def _purge_locked(self, now: float):
        expired = [key for key, item in self._tickets.items() if item.expires_at <= now]
        for key in expired:
            self._tickets.pop(key, None)
