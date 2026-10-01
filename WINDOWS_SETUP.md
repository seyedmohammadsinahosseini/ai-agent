# Running AI Terminal on your own Windows PC

This guide walks you through running the project natively on Windows — with
the real ConPTY-based C++ engine (not the Linux/POSIX fallback used in the
sandbox preview) and the Flutter app as an actual Windows desktop window.

## 0. Get the project files onto your PC

Clone the repository with a GitHub account that has access:

```powershell
git clone https://github.com/seyedmohammadsinahosseini/ai-terminal.git
cd ai-terminal
```

Use Git Credential Manager or SSH for a private repository. Never place a
personal access token directly in the clone URL or commit it to a file.

## 1. Install prerequisites

You'll need four things. Install them in this order:

### 1.1 Visual Studio Build Tools (for compiling the C++ engine)
The C++ engine needs a real Windows C++ compiler (MSVC), not MinGW/g++,
because it uses Win32/ConPTY headers.

1. Download **Visual Studio 2022 Community** (free): https://visualstudio.microsoft.com/downloads/
2. In the installer, select the **"Desktop development with C++"** workload.
   This also installs CMake integration, but we'll use a standalone CMake too.

### 1.2 CMake
Download and install from https://cmake.org/download/ (Windows x64 Installer).
During install, choose **"Add CMake to the system PATH"**.

### 1.3 Python 3.11+
Download from https://www.python.org/downloads/windows/
During install, check **"Add python.exe to PATH"**.

### 1.4 Flutter SDK
1. Download the Windows Flutter SDK zip: https://docs.flutter.dev/get-started/install/windows
2. Extract it somewhere like `C:\src\flutter` (avoid paths with spaces).
3. Add `C:\src\flutter\bin` to your PATH environment variable.
4. Open a **new** terminal (PowerShell) and run:
   ```powershell
   flutter doctor
   ```
   Make sure the "Visual Studio" and "Windows" checks are green. If Flutter
   complains about missing Visual Studio components, re-run the VS Installer
   and confirm the C++ workload from step 1.1 is checked.
5. Enable Windows desktop support (only needed once):
   ```powershell
   flutter config --enable-windows-desktop
   ```

## 2. Create one Python environment for both build and runtime

Open **PowerShell** in the repository root. Do not mix a globally installed
pybind11 from one Python version with a different Python selected by CMake.

```powershell
cd C:\path\to\ai-terminal

# Create and activate an isolated environment using your current Python.
python -m venv .venv
.\.venv\Scripts\Activate.ps1

python -m pip install --upgrade pip
python -m pip install -r server\requirements.txt pybind11 cmake

# These three paths must all point inside the same .venv/Python installation.
python -c "import sys; print(sys.executable)"
python -c "import pybind11; print(pybind11.__file__)"
python -c "import pybind11; print(pybind11.get_cmake_dir())"
```

If PowerShell blocks environment activation, run this once for the current
process and activate again:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\.venv\Scripts\Activate.ps1
```

## 3. Build the C++ engine (native Windows/ConPTY build)

Run these commands from the repository root with `.venv` still active:

```powershell
$pythonExe = (Get-Command python).Source
$pybind11Dir = python -c "import pybind11; print(pybind11.get_cmake_dir())"

# Always remove a build directory previously configured with another Python,
# generator, architecture, or source revision.
if (Test-Path engine\build) {
    Remove-Item -Recurse -Force engine\build
}

cmake -S engine -B engine\build `
  -DPython_EXECUTABLE="$pythonExe" `
  -Dpybind11_DIR="$pybind11Dir" `
  -DBUILD_TESTING=ON

cmake --build engine\build --config Release
ctest --test-dir engine\build -C Release --output-on-failure
```

A successful build produces files similar to:

```text
engine\build\Release\aiterm_engine.cp3XX-win_amd64.pyd
engine\build\Release\risk_classifier_test.exe
engine\build\Release\pty_session_test.exe
```

The `.pyd` filename must match the Python version printed by
`python -c "import sys; print(sys.version)"`. This native Windows build uses
ConPTY and a Windows Job Object for process-tree termination.

`engine_bridge.py` searches `engine/build/Release/`, `RelWithDebInfo/`, and
`Debug/` automatically, so no manual `PYTHONPATH` change is needed.

> The CMake messages about failing to find `pthread` are normal with MSVC.
> CMake ultimately reports `Found Threads: TRUE` using native Windows threads.

## 4. Set up and run the backend (FastAPI)

Keep the same `.venv` active:

```powershell
cd server
python -m app.main
```

You should see:
```
[AI Terminal] Local API listening on 127.0.0.1:8765 (token is not printed).
Uvicorn running on http://127.0.0.1:8765
```

The server writes the token to `%USERPROFILE%\.ai-terminal\local_api_token.txt`.
The native Flutter client reads that private file directly.

Leave this window running — it's your local API server. Note this defaults
to `host="127.0.0.1"` in the real build (loopback-only), unlike the sandbox
preview which had to bind `0.0.0.0` to be reachable through the proxy.

## 5. Run the Flutter app as a native Windows window

Open a **second** PowerShell window:

```powershell
cd C:\path\to\ai-terminal\client
flutter pub get
flutter run -d windows
```

This compiles and launches an actual Windows desktop app window (not a
browser tab). It talks to the backend at `http://127.0.0.1:8765` by default
(see `kDefaultDesktopServerUrl` in `lib/api_client.dart`).

For a distributable build (a folder you can zip and run without `flutter run`):
```powershell
flutter build windows
# Output executable + DLLs land in: client\build\windows\x64\runner\Release\
```

## 6. First run checklist

1. Click the **key icon** (top right) → add an API key for at least one
   provider (OpenAI, Anthropic, or Gemini — bring your own key).
2. Click the **folder icon** above the input box → pick a non-critical folder.
   Commands start there and common path escapes are blocked, but this is not
   an OS-level filesystem sandbox.
3. Try **Plan mode** first: ask a question, confirm the agent behaves
   read-only.
4. Switch to **Build mode** and try something small and reversible, like
   "create a file called hello.txt with some text in it," and watch the
   risk-level indicator + confirmation flow.

## Known gaps / what to expect

- **PowerShell execution**: ConPTY launches `powershell.exe` directly with
  `-NoLogo -NoProfile -NonInteractive`; commands should not wrap themselves
  in another `powershell -Command` layer.
- **Workspace boundary**: the path guard blocks common escapes, but it is not
  an AppContainer/VM filesystem sandbox. Use non-critical test folders.
- **Voice input is still a UI demo** (records briefly, inserts placeholder
  text) — real speech-to-text isn't wired in yet, as discussed.
- **No installer/code signing yet** — running via `flutter run -d windows`
  or the built `Release` folder is fine for testing, but Windows SmartScreen
  may warn on the unsigned `.exe` the first time you run the built version.
- The three independent safety layers (Plan/Build mode gate, C++
  `RiskClassifier`, and user confirmation dialogs) all run for real on
  Windows exactly as they did in the sandbox preview — nothing about the
  safety logic is different between platforms.

## If something doesn't build

### MSVC error C2589 in `pty_session.hpp`

Pull the latest source. Older revisions allowed the `min` macro from
`windows.h` to collide with `std::min`. The header now defines `NOMINMAX` before
including the Windows SDK.

```powershell
git pull
if (Test-Path engine\build) { Remove-Item -Recurse -Force engine\build }
```

Then repeat section 3 from a correctly activated `.venv`.

### CTest cannot find `risk_classifier_test.exe` or `pty_session_test.exe`

This is normally a consequence of the preceding C++ build failure. CTest does
not build missing executables. Fix the first compiler error, run
`cmake --build ... --config Release` successfully, and only then run CTest.

### `ModuleNotFoundError: No module named 'aiterm_engine'`

This means the native module was not built, was built for a different Python,
or is not under `engine\build\Release`. Check:

```powershell
Get-ChildItem engine\build\Release\aiterm_engine*.pyd
python -c "import sys; print(sys.executable); print(sys.version)"
```

If no `.pyd` is listed, the native build did not succeed. If its `cp3XX` tag
does not match the runtime Python, delete `engine\build` and rebuild from the
same activated `.venv`.

### CMake finds Python 3.14 but pybind11 under `Python312`

That is a mixed global/user installation. Do not continue with that build.
Activate `.venv`, install pybind11 through `python -m pip`, verify
`pybind11.__file__` is inside `.venv`, delete `engine\build`, and configure
again while passing `-DPython_EXECUTABLE="$pythonExe"`.

### Other common issues

- `cmake` cannot find pybind11: run `python -m pip show pybind11` and verify it
  uses the same activated interpreter as `python -c "import sys; print(sys.executable)"`.
- `flutter doctor` shows a red X next to Visual Studio: re-run Visual Studio
  Installer, enable **Desktop development with C++**, and restart PowerShell.
- A `.pyd` has the wrong Python tag: delete `engine\build` and rebuild with the
  same `.venv` used to start FastAPI.
