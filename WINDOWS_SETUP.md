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

### 1.3 Python 3.12 x64
Download the 64-bit Python 3.12 installer from
https://www.python.org/downloads/windows/. Keep the Python Launcher (`py`)
enabled during installation. The commands in this guide use `py -3.12`
explicitly, so no virtual environment or activation step is required.

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

## 2. Use one global Python installation for build and runtime

This project does not require a virtual environment. Open **PowerShell** in the
repository root and use the Windows Python Launcher to select Python 3.12 for
every package, build, diagnostic, and runtime command.

```powershell
cd C:\path\to\ai-terminal

# Confirm that the selected interpreter is 64-bit Python 3.12.
py -3.12 -c "import sys, struct; print(sys.executable); print(sys.version); print(struct.calcsize('P') * 8, 'bit')"

# Install into the current Windows account's Python 3.12 user site.
py -3.12 -m pip install --user --upgrade pip
py -3.12 -m pip install --user -r server\requirements.txt pybind11

# All three commands must describe the same Python 3.12 installation.
py -3.12 -c "import sys; print(sys.executable)"
py -3.12 -c "import pybind11; print(pybind11.__file__)"
py -3.12 -c "import pybind11; print(pybind11.get_cmake_dir())"
```

`--user` is not a virtual environment: packages are stored in the normal user
site for the global Python 3.12 installation. No activation command is needed.
Do not switch to an unversioned `python` or `pip` command later, because it may
resolve to Python 3.13 or 3.14 on a machine with several versions installed.

## 3. Build the C++ engine (native Windows/ConPTY build)

Run these commands from the repository root:

```powershell
$pythonExe = py -3.12 -c "import sys; print(sys.executable)"
$pythonRoot = Split-Path $pythonExe
$pybind11Dir = py -3.12 -c "import pybind11; print(pybind11.get_cmake_dir())"

# Always remove a build directory previously configured with another Python,
# generator, architecture, or source revision.
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

A successful build produces files similar to:

```text
engine\build\Release\aiterm_engine.cp3XX-win_amd64.pyd
engine\build\Release\risk_classifier_test.exe
engine\build\Release\pty_session_test.exe
```

The `.pyd` filename must have a Python 3.12 ABI tag such as `cp312`, matching
`py -3.12 -c "import sys; print(sys.version)"`. This native Windows build uses
ConPTY and a Windows Job Object for process-tree termination.

`engine_bridge.py` searches `engine/build/Release/`, `RelWithDebInfo/`, and
`Debug/` automatically, so no manual `PYTHONPATH` change is needed.

> The CMake messages about failing to find `pthread` are normal with MSVC.
> CMake ultimately reports `Found Threads: TRUE` using native Windows threads.

## 4. Set up and run the backend (FastAPI)

Use the same global Python 3.12 interpreter used for the native build; no
activation step is involved:

```powershell
cd server
py -3.12 -m app.main
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

Then repeat section 3 using the explicit global Python 3.12 commands.

### CTest cannot find `risk_classifier_test.exe` or `pty_session_test.exe`

This is normally a consequence of the preceding C++ build failure. CTest does
not build missing executables. Fix the first compiler error, run
`cmake --build ... --config Release` successfully, and only then run CTest.

### `pty_session_test` prints `pty-ok` but reports empty captured output

Pull the latest source and clean-rebuild. Older revisions allowed PowerShell to
inherit CTest's redirected standard output handle, bypassing ConPTY even though
the command exited successfully. The launcher now explicitly leaves the child
standard handles null so ConPTY creates them, then gives conhost a bounded
post-exit interval to flush trailing output.

```powershell
git pull
if (Test-Path engine\build) { Remove-Item -Recurse -Force engine\build }
```

Then repeat section 3 using `py -3.12` consistently.

### `ModuleNotFoundError: No module named 'aiterm_engine'`

This means the native module was not built, was built for a different Python,
or is not under `engine\build\Release`. Run these diagnostics from the
repository root in the same PowerShell window used to start the server:

```powershell
py -3.12 -c "import sys; print(sys.executable); print(sys.version)"
py -3.12 -c "import importlib.machinery; print(importlib.machinery.EXTENSION_SUFFIXES)"
Get-ChildItem engine\build\Release\aiterm_engine*.pyd

# Test the built module directly, independently of FastAPI.
$releaseDir = (Resolve-Path engine\build\Release).Path
py -3.12 -c "import sys; sys.path.insert(0, sys.argv[1]); import aiterm_engine; print(aiterm_engine.__file__)" $releaseDir
```

If no `.pyd` is listed, the native build did not succeed. If its ABI tag is
not `cp312`, or the direct import fails, perform this clean global-Python
rebuild:

```powershell
py -3.12 -m pip install --user --upgrade pip
py -3.12 -m pip install --user -r server\requirements.txt pybind11

$pythonExe = py -3.12 -c "import sys; print(sys.executable)"
$pythonRoot = Split-Path $pythonExe
$pybind11Dir = py -3.12 -c "import pybind11; print(pybind11.get_cmake_dir())"
py -3.12 -c "import sys; print(sys.executable); print(sys.version)"

if (Test-Path engine\build) { Remove-Item -Recurse -Force engine\build }
cmake -S engine -B engine\build `
  -G "Visual Studio 17 2022" `
  -A x64 `
  -DPython_EXECUTABLE="$pythonExe" `
  -DPython_ROOT_DIR="$pythonRoot" `
  -Dpybind11_DIR="$pybind11Dir" `
  -DBUILD_TESTING=ON
cmake --build engine\build --config Release
ctest --test-dir engine\build -C Release --output-on-failure

$releaseDir = (Resolve-Path engine\build\Release).Path
py -3.12 -c "import sys; sys.path.insert(0, sys.argv[1]); import aiterm_engine; print(aiterm_engine.__file__)" $releaseDir

Push-Location server
py -3.12 -m app.main
```

Do not configure CMake with one Python and launch FastAPI with another.
`engine_bridge.py` now preserves the original Python import/loader exception
and appends the active interpreter, recognized ABI suffixes, searched build
directories, and any native candidates it found.

### CMake finds Python 3.14 but pybind11 under `Python312`

That is a mixed global installation. Do not continue with that build. Delete
`engine\build`, obtain both `$pythonExe` and `$pybind11Dir` with `py -3.12` as
shown in section 3, and pass both paths explicitly to CMake. Starting FastAPI
with `py -3.12 -m app.main` guarantees the runtime uses that same interpreter.

### Other common issues

- `cmake` cannot find pybind11: run
  `py -3.12 -m pip show pybind11` and
  `py -3.12 -c "import pybind11; print(pybind11.get_cmake_dir())"`.
- `flutter doctor` shows a red X next to Visual Studio: re-run Visual Studio
  Installer, enable **Desktop development with C++**, and restart PowerShell.
- A `.pyd` has the wrong Python tag: delete `engine\build`, rebuild using the
  explicit Python 3.12 paths, and start FastAPI with `py -3.12`.
