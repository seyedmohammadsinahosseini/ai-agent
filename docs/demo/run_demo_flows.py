"""Drives the real AI Terminal server through demo conversations.

Uses only the app's public HTTP API (the same calls the UI makes):
  1. Plan mode  - SAFE read-only commands auto-execute in the C++ engine.
  2. Build mode - CONFIRM command stored *unconfirmed*; the UI confirmation
                  flow (Review & confirm -> Run it) executes it for the
                  screenshots in docs/demo/screenshots.py.
  3. Build mode - catastrophic command hits the native BLOCKED policy layer.

NOT part of the shipped application.
"""
import json
import pathlib
import urllib.request

BASE = "http://127.0.0.1:8765"
TOKEN = pathlib.Path("/home/user/.ai-terminal-demo/local_api_token.txt").read_text().strip()
WORKDIR = "/home/user/ai-terminal/demo_workspace"
PROVIDER = "custom:demo-local-model"
MODEL = "demo-terminal-1"


def call(method, path, body=None):
    req = urllib.request.Request(
        BASE + path,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"},
        method=method,
    )
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


res_chat_id = {"id": None}


def send_chat(history, text, mode):
    history.append({"role": "user", "content": text})
    res = call("POST", "/chat", {
        "messages": history,
        "provider": PROVIDER,
        "model": MODEL,
        "mode": mode,
        "working_dir": WORKDIR,
        "chat_id": res_chat_id.get("id"),
    })
    history.append({"role": "assistant", "content": res.get("reply_text", "")})
    res_chat_id["id"] = res["chat_id"]
    return res


print("### 1) Plan mode - SAFE auto-run (ls -la, cat notes.txt)")
history = []
r1 = send_chat(history, "Show me what's inside my project workspace.", "plan")
r2 = send_chat(history, "Nice. Now read notes.txt for me, what does it say?", "plan")
plan_chat = r2["chat_id"]
print(" risk1:", r1.get("risk_level"), "| risk2:", r2.get("risk_level"),
      "| auto2:", r2.get("auto_executed"))

print("### 2) Build mode - catastrophic command BLOCKED by the native engine")
# NOTE: the build-mode CONFIRM + confirm-in-UI flow is performed live in the
# browser by docs/demo/screenshots.py, so its chat is created there.
blocked_history = []
res_chat_id["id"] = None
r4 = send_chat(blocked_history, "Actually, just format my C drive with NTFS instead.", "build")
print(" risk:", r4.get("risk_level"), "| blocked_reason:", r4.get("blocked_reason"))

print("\nchats:")
for c in call("GET", "/chats")["chats"]:
    print("  -", c["id"], "|", c["title"])
