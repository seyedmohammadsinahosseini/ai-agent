# Running AI Terminal on your own Windows PC

This guide walks you through running the project natively on Windows — with
the real ConPTY-based C++ engine (not the Linux/POSIX fallback used in the
sandbox preview) and the Flutter app as an actual Windows desktop window.

## 0. Get the project files onto your PC

Since we haven't connected this to your GitHub yet, the simplest path for now:
download/copy the whole `ai-terminal/` folder from this workspace onto your
Windows machine (e.g. zip it up here and transfer it, or we set up GitHub
push later — just ask).

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

## 2. Build the C++ engine (native Windows/ConPTY build)

Open **PowerShell** in the project folder:

```powershell
cd ai-terminal\engine
mkdir build
cd build

# Find pybind11's cmake dir (pip install pybind11 first if needed)
pip install pybind11 cmake

cmake -Dpybind11_DIR="$(python -c 'import pybind11; print(pybind11.get_cmake_dir())')" ..
cmake --build . --config Release
```

If this succeeds, you should have a file like:
```
engine\build\Release\aiterm_engine.cp3XX-win_amd64.pyd
```

This `.pyd` file is the real Windows build — it uses `CreatePseudoConsole`
(ConPTY) instead of the Linux `forkpty` path, because `pty_session.hpp` picks
the right implementation automatically based on `#if defined(_WIN32)`.

> **Note:** `engine_bridge.py` already looks in `engine/build/Release/`,
> `RelWithDebInfo/`, and `Debug/` automatically, so no path editing is needed.

## 3. Set up and run the backend (FastAPI)

```powershell
cd ..\..\server
pip install -r requirements.txt
python -m app.main
```

You should see:
```
[AI Terminal] Local token (for client auth): <some long token>
Uvicorn running on http://127.0.0.1:8765
```

Leave this window running — it's your local API server. Note this defaults
to `host="127.0.0.1"` in the real build (loopback-only), unlike the sandbox
preview which had to bind `0.0.0.0` to be reachable through the proxy.

## 4. Run the Flutter app as a native Windows window

Open a **second** PowerShell window:

```powershell
cd ai-terminal\client
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

## 5. First run checklist

1. Click the **key icon** (top right) → add an API key for at least one
   provider (OpenAI, Anthropic, or Gemini — bring your own key).
2. Click the **folder icon** above the input box → pick a real folder you're
   comfortable letting the agent read/write in Build mode.
3. Try **Plan mode** first: ask a question, confirm the agent behaves
   read-only.
4. Switch to **Build mode** and try something small and reversible, like
   "create a file called hello.txt with some text in it," and watch the
   risk-level indicator + confirmation flow.

## Known gaps / what to expect

- **PowerShell vs cmd.exe**: the current ConPTY launcher runs commands
  through `cmd.exe /C "..."`. If the AI suggests PowerShell-only syntax, it
  currently needs to prefix it itself (e.g.
  `powershell -NoProfile -Command "..."`) — this works today but isn't the
  most polished experience yet. Let me know if you want the default shell
  switched to PowerShell directly.
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

The most common issues:
- `cmake` can't find pybind11 → make sure you ran `pip install pybind11` with
  the *same* Python that's on your PATH (check with `python -m pip show pybind11`).
- `flutter doctor` shows a red X next to Visual Studio → re-run the VS
  Installer, make sure "Desktop development with C++" is checked, restart
  your terminal.
- The `.pyd` file has a different Python version tag than your `python`
  (e.g. built for 3.12 but you're running 3.11) → rebuild the engine with
  the same Python version FastAPI is using, or create a venv and use it
  consistently for both.

Send me any error output and I'll help debug it directly.
