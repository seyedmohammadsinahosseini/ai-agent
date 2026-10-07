# Screenshot capture tooling

The PNGs in [`docs/images`](../images) are real captures of the Flutter web
build, driven end-to-end through the application's own HTTP/WebSocket API.
Nothing in these images is mocked on the client side: the safety gates and
command execution are the production code paths.

The only substitution is the AI provider: `mock_provider.py` runs a tiny
OpenAI-compatible "model" on `127.0.0.1:9909` that replies with scripted
`run_command` tool calls, connected to the app exactly like any custom
provider (Ollama, LM Studio, OpenRouter, ...).

## Reproduce

1. Build the native engine (see `WINDOWS_SETUP.md` / the CI workflow).
2. Build the web client: `cd client && flutter build web`.
3. Start the mock provider: `python mock_provider.py`.
4. Start the server with a development-only secrets fallback:
   `AITERM_ALLOW_PLAINTEXT_KEY_FALLBACK=1 python -m app.main`.
5. Register the provider (`POST /providers/custom`, base URL
   `http://127.0.0.1:9909/v1`), create the demo chats with
   `python run_demo_flows.py`, then capture the UI with
   `python screenshots.py` (Playwright + Chromium, using Flutter's
   accessibility tree to click real controls).
