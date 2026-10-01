import time

from app.security import WebSocketTicketStore, is_loopback_address, origin_is_allowed


def test_loopback_detection():
    assert is_loopback_address("127.0.0.1")
    assert is_loopback_address("::1")
    assert is_loopback_address("localhost")
    assert not is_loopback_address("192.168.1.10")


def test_origin_policy_allows_same_origin_and_rejects_foreign_site():
    allowed = ["http://127.0.0.1:8765"]
    assert origin_is_allowed(None, "127.0.0.1:8765", allowed)  # native client
    assert origin_is_allowed("http://127.0.0.1:8765", "127.0.0.1:8765", allowed)
    assert origin_is_allowed("https://preview.example", "preview.example", allowed)
    assert not origin_is_allowed("https://evil.example", "127.0.0.1:8765", allowed)


def test_websocket_tickets_are_one_use_and_expire():
    store = WebSocketTicketStore(ttl_seconds=1)
    ticket = store.issue()
    assert store.consume(ticket)
    assert not store.consume(ticket)

    expired_store = WebSocketTicketStore(ttl_seconds=0)
    expired = expired_store.issue()
    time.sleep(0.001)
    assert not expired_store.consume(expired)
