# AI Terminal client

Flutter user interface for AI Terminal. The production target is Windows
desktop; Flutter Web is supported for same-origin local development.

## Run

```bash
flutter pub get
flutter run -d windows
```

Start the FastAPI service first on `http://127.0.0.1:8765`. The native client
reads the local bearer token directly from
`~/.ai-terminal/local_api_token.txt` (or `%USERPROFILE%\.ai-terminal` on
Windows). If the server uses a custom `AITERM_HOME`, launch the client with the
same environment variable.

For a local web build:

```bash
flutter build web
```

The backend serves `build/web` when present. Web token bootstrap is restricted
to loopback and same/configured origins.

## Tests

```bash
flutter test
```

The widget tests cover mode switching and security-risk wire mappings. Keep
new interaction and regression tests under `test/`.
