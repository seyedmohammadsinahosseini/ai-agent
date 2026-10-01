# AI Terminal

AI Terminal is a local-first Windows desktop application that turns natural-language requests into reviewed, safety-gated PowerShell commands. It supports bring-your-own-key (BYOK) access to OpenAI, Anthropic, Google Gemini, and OpenAI-compatible providers.

> **Project status:** pre-release. The current build is suitable for development and controlled testing, not unattended use or critical systems.

## Why this project exists

Terminal automation is powerful, but allowing an AI model to execute arbitrary commands without an independent policy layer is unsafe. AI Terminal separates model suggestions from execution authorization:

- the model can propose one command;
- server-side policy decides whether the command is allowed;
- a native deterministic classifier assigns a risk level;
- non-read-only actions require user confirmation;
- catastrophic command patterns are permanently blocked.

The model never gets the final say on whether a command runs.

## Features

- Windows desktop interface built with Flutter.
- Local FastAPI service bound to loopback by default.
- Native C++ execution engine exposed through pybind11.
- Windows ConPTY execution with live output and Stop support.
- POSIX `forkpty` implementation for Linux/macOS development.
- Strict server-enforced Plan mode.
- Build mode with risk-aware confirmation flows.
- Deterministic risk levels:
  - `SAFE`: explicitly recognized read-only command;
  - `CONFIRM`: write operation or command not on the read-only allowlist;
  - `DANGEROUS`: privileged, destructive, encoded, or indirect execution;
  - `BLOCKED`: catastrophic operation that cannot run.
- Selected-workspace validation and common path-escape prevention.
- Provider-native tool/function calling with a compatibility fallback.
- Built-in OpenAI, Anthropic, and Gemini adapters.
- Custom OpenAI-compatible provider support.
- Local SQLite chat history.
- Persistent output for automatic and confirmed executions.
- Bounded file-context uploads with cleanup and filename hardening.
- OS credential-store integration for provider API keys.
- One-use, short-lived WebSocket execution tickets.

## Architecture at a glance

```text
┌─────────────────────────┐
│ Flutter desktop/web UI  │
│ client/                 │
└────────────┬────────────┘
             │ HTTP + WebSocket
             ▼
┌─────────────────────────┐
│ Local FastAPI service   │
│ server/                 │
│ policy, providers, data │
└────────────┬────────────┘
             │ pybind11
             ▼
┌─────────────────────────┐
│ Native C++ engine       │
│ engine/                 │
│ risk + PTY/ConPTY       │
└─────────────────────────┘
```

For the complete design, data flows, API surface, and trust boundaries, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Safety model

Execution authorization is repeated immediately before every command:

1. Validate and normalize the selected working directory.
2. Block common workspace escapes such as `..`, external absolute paths, UNC/device paths, environment/home shortcuts, and multiline commands.
3. Enforce Plan-mode read-only policy when Plan mode is active.
4. Classify the command in the native deterministic risk engine.
5. Require the appropriate user confirmation.
6. Verify that a confirmed command exactly matches the command stored on its originating assistant message.
7. Start the command in the validated working directory.

Only complete commands on the read-only allowlist may auto-run. Unknown commands are not considered safe.

### Workspace limitation

The workspace guard is defense in depth, **not an operating-system filesystem sandbox**. A script, compiler, package manager, or executable can perform system calls that cannot be fully understood from its command line. Commands run with the permissions of the current user.

Use non-critical test folders until an enforceable Windows AppContainer, VM, or brokered filesystem boundary is implemented. That work is tracked in [ROADMAP.md](ROADMAP.md).

## Repository layout

```text
ai-terminal/
├── client/                 Flutter user interface and Windows runner
├── engine/                 C++ risk classifier and PTY/ConPTY engine
│   └── tests/              Native regression and smoke tests
├── server/                 FastAPI service
│   ├── app/                API, provider, policy, storage, and security modules
│   └── tests/              Unit and integration tests
├── demo_workspace/         Non-critical sample workspace
├── ARCHITECTURE.md         System design and trust boundaries
├── CHANGELOG.md            Notable changes
├── DECISIONS.md            Architectural decision records
├── ROADMAP.md              Prioritized future work
└── WINDOWS_SETUP.md        Detailed native Windows setup guide
```

## Prerequisites

### Windows production/development target

- Windows 10 version 1809 or newer for ConPTY.
- Visual Studio 2022 with **Desktop development with C++**.
- CMake 3.15 or newer.
- Python 3.12 x64 is recommended for the documented Windows build.
- Flutter SDK with Windows desktop support enabled.

### Linux/macOS development

- A C++17 compiler.
- Python 3.11 or newer.
- CMake and pybind11.
- PTY development libraries available on the host.
- Flutter if the client will be built or tested.

## Quick start on Windows (without a virtual environment)

The supported workflow below does **not** create or activate a virtual
environment. It uses one explicitly selected global Python installation for
package installation, native compilation, and backend startup. The examples
use 64-bit Python 3.12 through the Windows Python Launcher. Do not mix
unversioned `python`/`pip` commands from another installation into these steps.

### 1. Install the Python packages globally for Python 3.12

Open PowerShell in the repository root:

```powershell
cd C:\path\to\ai-terminal

py -3.12 -c "import sys; print(sys.executable); print(sys.version)"
py -3.12 -m pip install --user --upgrade pip
py -3.12 -m pip install --user -r server\requirements-dev.txt pybind11
```

`--user` installs packages into the selected account's normal Python 3.12 user
site, not into the repository and not into a virtual environment. If Python
3.12 itself was installed only for your Windows account, a normal install
without `--user` is also valid; consistency of the interpreter is what matters.

### 2. Build and test the native engine

Delete any build directory previously configured with another Python, then
pass the exact Python 3.12 executable and pybind11 CMake directory explicitly:

```powershell
$pythonExe = py -3.12 -c "import sys; print(sys.executable)"
$pythonRoot = Split-Path $pythonExe
$pybind11Dir = py -3.12 -c "import pybind11; print(pybind11.get_cmake_dir())"

if (Test-Path engine\build) {
    Remove-Item -Recurse -Force engine\build
}

cmake -S engine -B engine\build `
  -G "Visual Studio 17 2022" `
  -A x64 `
  -DPython_EXECUTABLE="$pythonExe" `
  -DPython_ROOT_DIR="$pythonRoot" `
  -Dpybind11_DIR="$pybind11Dir" `
  -DBUILD_TESTING=ON

cmake --build engine\build --config Release
ctest --test-dir engine\build -C Release --output-on-failure
```

Both native tests must pass. Verify that Python 3.12 can load the resulting
module before starting FastAPI:

```powershell
$releaseDir = (Resolve-Path engine\build\Release).Path
py -3.12 -c "import sys; sys.path.insert(0, sys.argv[1]); import aiterm_engine; print(aiterm_engine.__file__)" $releaseDir
```

### 3. Start the local service

Keep this first PowerShell window open:

```powershell
cd server
py -3.12 -m app.main
```

The default address is `http://127.0.0.1:8765`. Verify it from another window
with `Invoke-RestMethod http://127.0.0.1:8765/health`. The long-lived local
bearer token is stored under `%USERPROFILE%\.ai-terminal` and is deliberately
not printed.

### 4. Start the Flutter client

In a second PowerShell window:

```powershell
cd C:\path\to\ai-terminal\client
flutter pub get
flutter run -d windows
```

For the optional same-origin web build:

```powershell
cd C:\path\to\ai-terminal\client
flutter build web
cd ..\server
py -3.12 -m app.main
```

Then open `http://127.0.0.1:8765`.

See [WINDOWS_SETUP.md](WINDOWS_SETUP.md) for the complete no-virtual-environment
Windows walkthrough and troubleshooting steps.

## Provider setup

Open **Settings** in the app and choose one of the following:

1. Add an API key for OpenAI, Anthropic, or Gemini.
2. Add a custom OpenAI-compatible provider using a label, base URL, API key, and optional model ID.

The server attempts live model discovery when the provider exposes a model-list endpoint. Static model metadata is only a fallback.

Provider keys are stored through the operating-system credential store using Python `keyring`. On Windows this uses Windows Credential Manager/DPAPI.

If a secure keyring backend is unavailable, key saving fails closed. A plaintext fallback exists only for isolated development and must be explicitly enabled:

```bash
export AITERM_ALLOW_PLAINTEXT_KEY_FALLBACK=1
```

Do not enable that option in a production build.

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `AITERM_HOME` | `~/.ai-terminal` | Local token, database, uploads, and development fallback location |
| `AITERM_HOST` | `127.0.0.1` | FastAPI bind address |
| `AITERM_ALLOWED_HOSTS` | `127.0.0.1,localhost,testserver` | Trusted HTTP Host values |
| `AITERM_ALLOWED_ORIGINS` | local port 8765 origins | Explicit browser CORS origins |
| `AITERM_ALLOW_REMOTE_WEB_BOOTSTRAP` | `0` | Development-only opt-in for remote web preview bootstrap |
| `AITERM_ALLOW_PLAINTEXT_KEY_FALLBACK` | `0` | Development-only plaintext secret fallback |
| `API_BASE_URL` | empty | Flutter compile-time API override; native default is loopback |

A non-loopback deployment changes the threat model and is not supported as a production configuration.

## Tests

### Python unit and integration tests

Windows with the documented global Python installation:

```powershell
py -3.12 -m pytest server\tests -q
```

Linux/macOS:

```bash
PYTHONPATH=server python3 -m pytest -q server/tests
```

The integration suite automatically skips native execution tests when the C++ module has not been built.

### Native tests

Windows:

```powershell
cmake --build engine\build --config Release
ctest --test-dir engine\build -C Release --output-on-failure
```

Linux/macOS:

```bash
cmake --build engine/build
ctest --test-dir engine/build --output-on-failure
```

### Flutter tests

```bash
cd client
flutter test
```

### Regenerate product icons

```powershell
py -3.12 -m pip install --user Pillow
py -3.12 client\tool\generate_icons.py
```

## Local data and privacy

Stored locally:

- provider keys in the OS credential store;
- the local API token in the private app directory;
- chat history and execution metadata in SQLite;
- temporary context uploads until consumed, discarded, or expired.

Sent to the selected AI provider when needed:

- user and assistant conversation turns;
- proposed-command and bounded execution context;
- bounded text extracted from context attachments;
- selected workspace description and active mode.

Attachment contents and command output are treated as untrusted data in the provider prompt, but prompt-injection resistance is not a substitute for execution policy.

## Current limitations

- No enforceable Windows filesystem/network sandbox yet.
- No snapshot, undo, or Recycle Bin integration.
- No automatic secret redaction before command output is included in a later provider request.
- Context extraction is plain-text only.
- Voice input is currently a labelled UI demonstration.
- No signed installer, secure updater, or packaged server lifecycle yet.
- No durable append-only audit log.
- Provider APIs and model identifiers can change independently of this project.

## Project documents

- [ROADMAP.md](ROADMAP.md) — priorities, release gates, and future work.
- [ARCHITECTURE.md](ARCHITECTURE.md) — components, flows, security boundaries, and API surface.
- [CHANGELOG.md](CHANGELOG.md) — notable changes by release state.
- [DECISIONS.md](DECISIONS.md) — accepted architectural decisions and consequences.
- [WINDOWS_SETUP.md](WINDOWS_SETUP.md) — native Windows build instructions.

## Security notes for contributors

- Never commit API keys, local bearer tokens, or credential-bearing Git remotes.
- Add regression tests for every risk-classifier or policy change.
- Treat model output, uploaded content, and command output as untrusted input.
- Do not weaken server-side checks to solve a UI-only problem.
- Do not describe the workspace guard as a complete sandbox.

## Release policy

The repository does not currently publish a stable tagged release. Until the release gates in [ROADMAP.md](ROADMAP.md) are met, changes are documented under the `Unreleased` section of [CHANGELOG.md](CHANGELOG.md).
