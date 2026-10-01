"""
AI Terminal local FastAPI server.

Security notes:
- Only listens on 127.0.0.1 in the final build (see bottom of file).
- Every request (except health/local-token) requires an
  `Authorization: Bearer <local_token>` header.
- Plan mode is enforced server-side (not just hidden in the UI) via
  execution_service.authorize(), which is a hard gate independent of what the
  AI model itself suggests.
"""
import asyncio
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, Depends, HTTPException, Header, WebSocket, WebSocketDisconnect, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from .config import (
    get_or_create_local_token, save_provider_api_key, list_configured_providers,
    delete_provider_api_key,
    save_custom_provider, list_custom_providers, delete_custom_provider,
)
from .models import (
    ChatRequest, ChatResponse, SuggestedCommand,
    ExecuteRequest, ExecuteResponse,
    SaveApiKeyRequest, ProviderStatus,
    CustomProviderCreate, CustomProviderInfo,
    BrowseFolderResponse, SelectWorkingDirRequest, SelectWorkingDirResponse,
    UploadResponse,
)
from . import engine_bridge
from . import workspace
from . import uploads
from . import model_catalog
from .ai_providers import suggest_command, discover_models, ProviderError
from .execution_service import authorize

app = FastAPI(title="AI Terminal Local API", version="0.2.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # PoC only; restrict in the final build
    allow_methods=["*"],
    allow_headers=["*"],
)

LOCAL_TOKEN = get_or_create_local_token()


def verify_token(authorization: Optional[str] = Header(None)):
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    token = authorization.removeprefix("Bearer ").strip()
    if token != LOCAL_TOKEN:
        raise HTTPException(status_code=403, detail="Invalid local token")
    return True


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/local-token")
def get_local_token():
    """
    PoC/dev only: in the final build, the token should be read directly from
    the local file by the Flutter app itself (same machine), not exposed over
    an unauthenticated HTTP endpoint.
    """
    return {"token": LOCAL_TOKEN}


# ------------------------------- Providers / models -------------------------------

@app.get("/providers/status", response_model=ProviderStatus, dependencies=[Depends(verify_token)])
def providers_status():
    configured = list_configured_providers()
    custom = list_custom_providers()
    models = model_catalog.models_for_configured_providers(configured) + \
        model_catalog.models_for_custom_providers(custom)
    return ProviderStatus(
        configured_providers=configured,
        available_models=models,
        custom_providers=[CustomProviderInfo(**p) for p in custom],
    )


@app.post("/providers/api-key", dependencies=[Depends(verify_token)])
def set_api_key(req: SaveApiKeyRequest):
    save_provider_api_key(req.provider, req.api_key)
    return {"ok": True}


@app.delete("/providers/api-key/{provider}", dependencies=[Depends(verify_token)])
def remove_api_key(provider: str):
    """Lets the user remove a saved built-in provider key (e.g. to replace it
    with a key from a different account) without restarting the app."""
    delete_provider_api_key(provider)
    return {"ok": True}


@app.post("/providers/custom", response_model=CustomProviderInfo, dependencies=[Depends(verify_token)])
async def add_custom_provider(req: CustomProviderCreate):
    """Connect an arbitrary OpenAI-API-compatible provider by URL (Groq,
    OpenRouter, Together, DeepSeek, a self-hosted Ollama/LM Studio server,
    etc.) instead of picking from the built-in OpenAI/Anthropic/Gemini
    presets. If no model is given, the server tries to auto-detect which
    models the key can access via GET {base_url}/models."""
    base_url = req.base_url.strip()
    if not (base_url.startswith("http://") or base_url.startswith("https://")):
        raise HTTPException(status_code=400, detail="Base URL must start with http:// or https://")

    models: list[str] = []
    if req.model:
        models = [req.model.strip()]
    else:
        models = await discover_models(base_url, req.api_key)
        if not models:
            raise HTTPException(
                status_code=400,
                detail="Couldn't auto-detect any models for this URL/key. "
                       "Please enter a model id manually.",
            )

    entry = save_custom_provider(label=req.label.strip(), base_url=base_url,
                                  api_key=req.api_key, models=models)
    return CustomProviderInfo(**entry)


@app.delete("/providers/custom/{provider_id}", dependencies=[Depends(verify_token)])
def remove_custom_provider(provider_id: str):
    delete_custom_provider(provider_id)
    return {"ok": True}


# ------------------------------- Working directory -------------------------------

@app.get("/workspace/browse", response_model=BrowseFolderResponse, dependencies=[Depends(verify_token)])
def browse_folder(path: Optional[str] = None):
    return workspace.browse(path)


@app.post("/workspace/select", response_model=SelectWorkingDirResponse, dependencies=[Depends(verify_token)])
def select_working_dir(req: SelectWorkingDirRequest):
    ok, result = workspace.resolve_working_dir(req.path)
    if ok:
        return SelectWorkingDirResponse(path=result, ok=True)
    return SelectWorkingDirResponse(path=req.path, ok=False, message=result)


# ------------------------------- Uploads -------------------------------

@app.post("/uploads", response_model=UploadResponse, dependencies=[Depends(verify_token)])
async def upload_file(
    file: UploadFile = File(...),
    kind: str = Form("context"),
    working_dir: Optional[str] = Form(None),
):
    data = await file.read()
    try:
        if kind == "workspace":
            if not working_dir:
                raise HTTPException(status_code=400, detail="Select a working folder before uploading into it.")
            stored = uploads.save_workspace_upload(file.filename or "file", data, working_dir)
        else:
            stored = uploads.save_context_upload(file.filename or "file", data)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    return UploadResponse(id=stored.id, filename=stored.filename, size_bytes=stored.size_bytes,
                           kind=stored.kind, saved_path=stored.saved_path)


# ------------------------------- Chat -------------------------------

@app.post("/chat", response_model=ChatResponse, dependencies=[Depends(verify_token)])
async def chat(req: ChatRequest):
    messages = list(req.messages)

    # Inline any "context" attachments' text content as an extra system-ish message
    attachment_texts = []
    for att_id in req.attachment_ids:
        text = uploads.read_context_text(att_id)
        upload = uploads.get_upload(att_id)
        if text is not None and upload:
            attachment_texts.append(f"--- Attached file: {upload.filename} ---\n{text}")
    if attachment_texts:
        from .models import ChatMessage
        messages = messages + [ChatMessage(role="user", content="\n\n".join(attachment_texts))]

    try:
        result = await suggest_command(messages, req.provider, req.model, req.mode, req.working_dir)
    except ProviderError as e:
        raise HTTPException(status_code=400, detail=str(e))

    reply_text = result.get("reply_text") or ""
    command = result.get("command")
    explanation = result.get("explanation") or ""

    response = ChatResponse(reply_text=reply_text, mode=req.mode)

    if command:
        response.suggested_command = SuggestedCommand(command=command, explanation=explanation)

        # Server-side authorization check purely to *report* the risk level in
        # the chat response; actual execution still goes through /execute or
        # /ws/execute, which re-run this same check (defense in depth - never
        # trust a client-cached decision).
        auth = authorize(command, req.mode, user_confirmed=False, confirmation_phrase=None)
        response.risk_level = auth.risk_level
        response.risk_human_reason = auth.risk_human_reason

        if auth.allowed and auth.risk_level == "SAFE":
            exec_result = engine_bridge.run_command_sync(command, req.working_dir)
            response.auto_executed = True
            response.execution_output = exec_result.output
            response.execution_exit_code = exec_result.exit_code
        elif not auth.allowed and auth.risk_level == "BLOCKED_BY_MODE":
            response.blocked_reason = auth.message
        elif not auth.allowed and auth.risk_level == "BLOCKED":
            response.blocked_reason = auth.message

    return response


# ------------------------------- Execute (REST, one-shot) -------------------------------

@app.post("/execute", response_model=ExecuteResponse, dependencies=[Depends(verify_token)])
def execute(req: ExecuteRequest, mode: str = "build"):
    auth = authorize(req.command, mode, req.user_confirmed, req.confirmation_phrase)
    if not auth.allowed:
        return ExecuteResponse(executed=False, risk_level=auth.risk_level,
                                risk_human_reason=auth.risk_human_reason, message=auth.message)

    exec_result = engine_bridge.run_command_sync(req.command, req.working_dir)
    return ExecuteResponse(executed=True, risk_level=auth.risk_level,
                            risk_human_reason=auth.risk_human_reason,
                            output=exec_result.output, exit_code=exec_result.exit_code)


# ------------------------------- Execute (WebSocket, streaming + stoppable) -------------------------------

@app.websocket("/ws/execute")
async def ws_execute(websocket: WebSocket):
    """
    Streaming execution channel that also supports a real Stop button:
    the client can send {"type": "stop"} at any time to kill the running
    process via the native engine's kill_execution().
    """
    token = websocket.query_params.get("token")
    if token != LOCAL_TOKEN:
        await websocket.close(code=4403)
        return

    await websocket.accept()
    loop = asyncio.get_event_loop()
    active_execution_id: Optional[int] = None
    send_lock = asyncio.Lock()

    async def safe_send(payload: dict):
        # Multiple tasks (the reader loop + native-thread callbacks) may send
        # concurrently; a lock avoids interleaved/corrupted WebSocket frames.
        # Swallow send errors caused by the client having already disconnected
        # (e.g. a command finishes right as the user closes the tab).
        async with send_lock:
            try:
                await websocket.send_json(payload)
            except (WebSocketDisconnect, RuntimeError):
                pass

    try:
        while True:
            data = await websocket.receive_json()
            msg_type = data.get("type", "run")

            if msg_type == "stop":
                # This must be handled immediately even while a command is
                # running, which is why message reading happens in this same
                # loop rather than being blocked behind a "wait for done"
                # call - the run below is dispatched to the background
                # native thread and does NOT block this receive loop.
                if active_execution_id is not None:
                    engine_bridge.kill_execution(active_execution_id)
                else:
                    await safe_send({"type": "stop_ack", "message": "Nothing is currently running."})
                continue

            command = data.get("command", "")
            mode = data.get("mode", "build")
            working_dir = data.get("working_dir")
            user_confirmed = data.get("user_confirmed", False)
            confirmation_phrase = data.get("confirmation_phrase")

            auth = authorize(command, mode, user_confirmed, confirmation_phrase)
            if not auth.allowed:
                await safe_send({
                    "type": "rejected", "risk_level": auth.risk_level, "message": auth.message,
                })
                continue

            if active_execution_id is not None:
                await safe_send({"type": "rejected", "risk_level": "BUSY",
                                  "message": "Another command is already running. Stop it first."})
                continue

            execution_id = engine_bridge.new_execution_id()
            active_execution_id = execution_id

            await safe_send({"type": "started", "risk_level": auth.risk_level,
                              "execution_id": execution_id})

            def on_chunk(chunk: str, loop=loop):
                loop.call_soon_threadsafe(
                    lambda: asyncio.ensure_future(safe_send({"type": "output", "data": chunk}))
                )

            def on_done(exit_code: int, loop=loop):
                def _mark_and_send():
                    nonlocal active_execution_id
                    active_execution_id = None
                    asyncio.ensure_future(safe_send({"type": "done", "exit_code": exit_code}))
                loop.call_soon_threadsafe(_mark_and_send)

            engine_bridge.start_streaming_execution(
                execution_id, command, working_dir, on_chunk, on_done,
            )
            # NOTE: no `await` on completion here - we immediately loop back to
            # receive_json() so a "stop" message can be processed while the
            # command is still running in the background.

    except WebSocketDisconnect:
        if active_execution_id is not None:
            engine_bridge.kill_execution(active_execution_id)


# --------------------------------------------------------------------------
# PoC ONLY: FastAPI also serves the built Flutter Web bundle so everything
# runs on a single origin inside the sandbox preview. In the final Windows
# Desktop build, Flutter is a separate native app and this block doesn't
# exist.
_WEB_BUILD_DIR = Path(__file__).resolve().parents[2] / "client" / "build" / "web"
if _WEB_BUILD_DIR.exists():
    app.mount("/", StaticFiles(directory=str(_WEB_BUILD_DIR), html=True), name="web-client")
# --------------------------------------------------------------------------


if __name__ == "__main__":
    import uvicorn
    import os
    print(f"[AI Terminal] Local token (for client auth): {LOCAL_TOKEN}")
    host = os.environ.get("AITERM_HOST", "127.0.0.1")
    uvicorn.run(app, host=host, port=8765)
