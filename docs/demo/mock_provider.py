"""Local OpenAI-compatible demo provider used only for documentation screenshots.

Runs a tiny scripted "model" on 127.0.0.1:9909 that responds to the app's
chat-completions requests with a `run_command` tool call chosen from the last
user message. This exercises the app's real custom-provider pipeline (the
same code path used for Ollama / LM Studio / OpenRouter etc.).

NOT part of the shipped application.
"""
import json

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

app = FastAPI()

# (keyword in last user message, command, explanation, friendly reply)
RULES = [
    ("format", "format C: /fs:ntfs /q",
     "Formats the entire C: drive with a quick format.",
     "That request would wipe a whole drive, so I'll only show you what it "
     "would look like - the safety layer makes the final call."),
    ("notes", "cat notes.txt",
     "Prints the contents of notes.txt in the selected workspace.",
     "Sure - reading notes.txt from your workspace now."),
    ("readme", "echo \"# Demo workspace\" > README.md",
     "Creates README.md in the workspace containing a top-level heading.",
     "I'll drop a small README.md with a title into the workspace."),
    ("reports", "mkdir -p reports && date > reports/generated.txt && cat reports/generated.txt",
     "Creates a reports/ folder in the workspace, writes today's date into reports/generated.txt and prints it back.",
     "I'll set up the reports folder and drop a timestamp file inside it."),
    ("list", "ls -la",
     "Lists every file in the selected workspace, including hidden files.",
     "Here is what's inside your project workspace:"),
]
DEFAULT = RULES[-1]


def _pick(last_user: str):
    lowered = last_user.lower()
    for keyword, command, explanation, reply in RULES:
        if keyword in lowered:
            return command, explanation, reply
    return DEFAULT[1], DEFAULT[2], DEFAULT[3]


@app.get("/v1/models")
def models():
    return {"data": [{"id": "demo-terminal-1", "object": "model", "owned_by": "local"}]}


@app.post("/v1/chat/completions")
async def completions(request: Request):
    body = await request.json()
    user_msgs = [m for m in body.get("messages", []) if m.get("role") == "user"]
    last_user = user_msgs[-1].get("content", "") if user_msgs else ""
    command, explanation, reply = _pick(last_user)

    message = {
        "role": "assistant",
        "content": reply,
        "tool_calls": [{
            "id": "call_demo_1",
            "type": "function",
            "function": {
                "name": "run_command",
                "arguments": json.dumps({"command": command, "explanation": explanation}),
            },
        }],
    }
    return JSONResponse({
        "id": "chatcmpl-demo",
        "object": "chat.completion",
        "model": body.get("model", "demo-terminal-1"),
        "choices": [{"index": 0, "message": message, "finish_reason": "tool_calls"}],
        "usage": {"prompt_tokens": 10, "completion_tokens": 10, "total_tokens": 20},
    })


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=9909, log_level="warning")
