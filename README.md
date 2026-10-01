# AI Terminal

A Windows desktop app that lets you get things done on your computer using
natural language, powered by an AI model of your choice. You bring your own
API key (BYOK) - OpenAI, Anthropic, Gemini, or any other OpenAI-API-compatible
provider by URL (Groq, OpenRouter, Together, DeepSeek, a self-hosted
Ollama/LM Studio server, etc.).

```
Flutter UI (client/)  <--HTTP/WebSocket-->  FastAPI (server/)  <--pybind11-->  C++ Engine (engine/)
```

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full design.

## What it does

- **C++ engine (`engine/`)**: a `RiskClassifier` deterministically classifies
  every command into `SAFE` / `CONFIRM` / `DANGEROUS` / `BLOCKED`, completely
  independent of what the AI model itself says. A `PtySession` class runs
  commands in a real pseudo-terminal - Windows ConPTY on the native build,
  POSIX `forkpty` for Linux/macOS development and testing.
- **FastAPI server (`server/`)**: a local-only API (`127.0.0.1:8765`) that:
  - Talks to the AI provider you configure (BYOK), including any custom
    OpenAI-API-compatible provider added by URL.
  - Sends every AI-suggested command through the C++ risk classifier before
    it's allowed to run.
  - Auto-executes `SAFE` commands, asks for explicit confirmation on
    `CONFIRM`/`DANGEROUS` commands, and never runs `BLOCKED` ones.
  - Enforces **Plan mode** (read-only) as a hard, server-side gate - not just
    a UI toggle - so the agent genuinely can't modify anything until you
    switch to **Build mode**.
  - Requires a local bearer token (generated on first run) on every request.
- **Flutter client (`client/`)**: a modern, SaaS-style chat interface with:
  - A Plan/Build mode switch next to the message input.
  - A working-folder picker so you control exactly where the agent can act.
  - File upload, letting you choose per file whether it's just context for
    the AI or something to place into the working folder.
  - Color-coded risk levels on every suggested command, with a strong
    type-to-confirm dialog for dangerous ones.
  - A floating, provider-grouped model picker, and a separate settings panel
    for managing API keys and custom providers.

## Running it locally (development)

```bash
# 1) Build the C++ engine
cd engine && mkdir -p build && cd build
cmake -Dpybind11_DIR=$(python3 -c "import pybind11; print(pybind11.get_cmake_dir())") ..
cmake --build . -j4

# 2) Install Python dependencies and run the server
cd ../../server
pip install -r requirements.txt
python3 -m app.main
# Server comes up on http://127.0.0.1:8765

# 3) Build and run the client (Web build, for quick testing without Windows)
cd ../client
flutter pub get
flutter build web
# build/web is served automatically by the same FastAPI server
```

Then open `http://127.0.0.1:8765` in your browser.

For running the **real native Windows desktop app** (not the web preview),
see [`WINDOWS_SETUP.md`](WINDOWS_SETUP.md) for the full step-by-step guide,
including installing Visual Studio Build Tools, CMake, and Flutter's Windows
desktop target.

## Connecting an AI provider

Two ways to connect a model:
1. **Built-in presets** - OpenAI, Anthropic, or Google Gemini. Just paste
   your API key in Settings.
2. **Any other provider, by URL** - if a company exposes an
   OpenAI-compatible `/chat/completions` endpoint (this is a very common
   standard - Groq, OpenRouter, Together, DeepSeek, Fireworks, a self-hosted
   Ollama/LM Studio server, etc.), you can connect it directly: give it a
   name, its base URL (e.g. `https://api.groq.com/openai/v1`), and your key.
   If you leave the model field blank, the app tries to auto-detect which
   models your key can access via the provider's `/models` endpoint.

## Deliberately simplified in this build, and left for a future iteration

- Real OS-level sandboxing of executed commands (e.g. Windows Job Objects).
- Automatic redaction of sensitive output (passwords, tokens) before it's
  sent to a cloud AI provider.
- Durable, structured audit logging (currently just uvicorn's own log).
- Snapshot/undo support (System Restore Point, or soft-delete to Recycle Bin
  instead of permanent deletion).
- Code-signing and MSIX/installer packaging of the final binaries.
- Deeper adversarial testing of `risk_classifier.hpp` against a wider set of
  PowerShell/cmd obfuscation patterns.
- Real voice-to-text (the mic button is currently a clearly-labeled UI demo).
