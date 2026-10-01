import os
from pathlib import Path

import pytest

pytest.importorskip("fastapi")

ROOT = Path(__file__).resolve().parents[2]
ENGINE_BUILD = ROOT / "engine" / "build"
ENGINE_SEARCH_DIRS = [
    ENGINE_BUILD,
    ENGINE_BUILD / "Release",
    ENGINE_BUILD / "RelWithDebInfo",
    ENGINE_BUILD / "Debug",
]
if not any(directory.exists() and any(directory.glob("aiterm_engine*"))
           for directory in ENGINE_SEARCH_DIRS):
    pytest.skip("native engine has not been built", allow_module_level=True)

from fastapi.testclient import TestClient
from app import chat_store
from app.config import APP_DIR
from app.main import app, LOCAL_TOKEN


def test_authenticated_execute_and_websocket_persistence():
    client = TestClient(app)
    integration_command = "Write-Output integration-ok" if os.name == "nt" else "printf integration-ok"
    websocket_command = "Write-Output websocket-ok" if os.name == "nt" else "printf websocket-ok"
    headers = {"Authorization": f"Bearer {LOCAL_TOKEN}"}
    # TestClient is not a loopback IP; remote bootstrap is denied by default.
    assert client.get("/local-token").status_code == 403

    blocked = client.post("/execute?mode=plan", headers=headers, json={
        "command": "echo changed > integration-write.txt",
        "working_dir": str(APP_DIR),
    })
    assert blocked.status_code == 200
    assert blocked.json()["risk_level"] == "BLOCKED_BY_MODE"
    assert not (APP_DIR / "integration-write.txt").exists()

    rest_chat = chat_store.create_chat("REST execution")
    rest_message = chat_store.add_message(
        rest_chat["id"], "assistant", "Run it",
        extra={"suggested_command": {"command": integration_command, "explanation": "test"}},
    )
    tampered = client.post("/execute?mode=build", headers=headers, json={
        "command": "Write-Output tampered" if os.name == "nt" else "printf tampered",
        "working_dir": str(APP_DIR),
        "user_confirmed": True,
        "chat_id": rest_chat["id"],
        "message_id": rest_message["id"],
    })
    assert tampered.json()["executed"] is False
    assert tampered.json()["risk_level"] == "INVALID_REQUEST"

    run = client.post("/execute?mode=build", headers=headers, json={
        "command": integration_command,
        "working_dir": str(APP_DIR),
        "user_confirmed": True,
        "chat_id": rest_chat["id"],
        "message_id": rest_message["id"],
    })
    assert run.status_code == 200
    assert run.json()["executed"] is True
    assert "integration-ok" in run.json()["output"]
    chat_store.delete_chat(rest_chat["id"])

    chat = chat_store.create_chat("WebSocket persistence")
    message = chat_store.add_message(
        chat["id"], "assistant", "Run it",
        extra={"suggested_command": {"command": websocket_command, "explanation": "test"}},
    )
    ticket = client.post("/ws-ticket", headers=headers).json()["ticket"]

    with client.websocket_connect(f"/ws/execute?ticket={ticket}") as socket:
        socket.send_json({
            "type": "run",
            "command": websocket_command,
            "mode": "build",
            "working_dir": str(APP_DIR),
            "user_confirmed": True,
            "chat_id": chat["id"],
            "message_id": message["id"],
        })
        streamed = ""
        while True:
            event = socket.receive_json()
            if event["type"] == "output":
                streamed += event["data"]
            if event["type"] == "done":
                break

    assert "websocket-ok" in streamed
    saved = chat_store.get_chat(chat["id"])["messages"][0]
    assert "websocket-ok" in saved["execution_output"]
    assert saved["execution_exit_code"] == 0
    chat_store.delete_chat(chat["id"])
