# AI Terminal - Architecture

## Layers

```
Flutter UI  <--HTTP/WebSocket-->  FastAPI (Python)  <--pybind11-->  C++ Engine
   client/                           server/                          engine/
```

- **engine/**: a C++ module exported to Python via pybind11.
  - `pty_session`: runs a command inside a real pseudo-terminal. On the
    native Windows build this uses ConPTY (`CreatePseudoConsole`); on
    Linux/macOS (used for development and testing) it uses POSIX `forkpty`.
    Both branches expose the same API (`run`, `run_in_dir`, `start_async`,
    `start_async_in_dir`, `kill_execution`), so the rest of the app doesn't
    need to know or care which platform it's running on.
  - `risk_classifier`: a pure, deterministic C++ function that classifies
    every command into one of `SAFE` / `CONFIRM` / `DANGEROUS` / `BLOCKED`.
    This layer is completely independent of the AI model's own output - it's
    a defense-in-depth measure against a model mistake or a prompt
    injection attempt.

- **server/**: a FastAPI service that only listens on `127.0.0.1`.
  - `/chat`: takes the user's message, forwards it (plus the current
    Plan/Build mode and working directory) to the configured AI provider
    (OpenAI/Anthropic/Gemini, or any custom OpenAI-API-compatible provider -
    BYOK throughout), and returns the model's suggested command, if any.
  - `/execute`: runs a command through the C++ risk classifier and, if
    authorized, actually executes it.
  - `/ws/execute`: a WebSocket channel for streaming live command output
    back to the client as it's produced.
  - `/providers/status`, `/providers/api-key`, `/providers/custom`: manage
    BYOK credentials, including arbitrary custom providers added by URL.
  - `/workspace/browse`, `/workspace/select`: let the user pick which folder
    the agent is allowed to operate in.
  - `/uploads`: handles file uploads, tagged as either AI context or content
    to place into the working folder.
  - Authentication is a random local bearer token (generated on first run
    and never exposed outside localhost).

- **client/**: the Flutter app. Runs as a native Windows desktop window in
  the final build (`flutter run -d windows` / `flutter build windows`); a
  Web build is also available for quick previewing without a Windows
  machine (served directly by the FastAPI server).

## Anatomy of a request

1. The user types, in the chat: "clean up the old files in Downloads."
2. FastAPI sends this message (with conversation history, the active
   Plan/Build mode, and the selected working folder) to the configured AI
   provider. The model returns a suggested command (e.g.
   `Remove-Item -Recurse ...`) plus a plain-language explanation.
3. FastAPI passes the command to the C++ `risk_classifier`.
4. If the mode is **Plan**, anything beyond a safe, read-only command is
   rejected server-side, regardless of what the model suggested - this is a
   hard gate, not just a UI restriction.
5. In **Build** mode: `SAFE` commands run immediately and stream their
   output; `CONFIRM` or `DANGEROUS` commands are shown to the user in the UI
   and wait for explicit confirmation (dangerous ones require typing a
   confirmation phrase).
6. The command's live output (via ConPTY/PTY) is streamed to the Flutter
   client over the WebSocket connection.

## Multi-provider model support (BYOK)

- Built-in presets (OpenAI, Anthropic, Gemini) each have a small hardcoded
  model catalog and a dedicated request/response adapter, since each speaks
  a slightly different API shape.
- Any other company that exposes an OpenAI-compatible `/chat/completions`
  endpoint can be connected as a **custom provider**: the user supplies a
  label, base URL, and API key. The server tries `GET {base_url}/models` to
  auto-detect which models the key can access; if that isn't supported, the
  user can type a model id manually. Custom providers are addressed
  internally as `custom:<slug>` and flow through the exact same risk
  classification and mode-gating pipeline as the built-in ones - there's no
  separate, weaker code path for them.

## Security measures implemented so far

- Risk classification lives in C++, not just in the model's system prompt.
- Plan-mode read-only enforcement happens server-side
  (`execution_service.authorize()`), independent of the AI model's output.
- Working directories and commands are passed to the native engine directly
  (no shell string concatenation / `cd &&` prefixing), avoiding a whole
  class of shell-injection bugs.
- API keys are stored via the OS credential store (`keyring`, which uses
  Windows Credential Manager/DPAPI on Windows) rather than hardcoded or
  stored in plaintext config.
- The API only listens on loopback (`127.0.0.1`), and every request requires
  a local bearer token generated on first run.

## Known gaps (tracked, not yet implemented)

See the "Deliberately simplified" section of the top-level `README.md`.
