"""
Bridge to the native C++ engine (aiterm_engine.so on Linux/macOS,
aiterm_engine.pyd on Windows).

In the final Windows build, this native module ships alongside the main
executable. Here we add the build directory to sys.path so the import works
during development.
"""
import importlib.machinery
import itertools
import sys
from pathlib import Path

_ENGINE_BUILD_DIR = Path(__file__).resolve().parents[2] / "engine" / "build"
_ENGINE_SEARCH_DIRS = [_ENGINE_BUILD_DIR] + [
    _ENGINE_BUILD_DIR / sub for sub in ("Release", "RelWithDebInfo", "Debug")
]
for _path in _ENGINE_SEARCH_DIRS:
    if _path.exists() and str(_path) not in sys.path:
        sys.path.insert(0, str(_path))

_ENGINE_CANDIDATES = sorted(
    str(path)
    for directory in _ENGINE_SEARCH_DIRS if directory.exists()
    for path in directory.glob("aiterm_engine*")
    if path.is_file() and path.suffix.lower() in {".pyd", ".so", ".dylib"}
)
_ENGINE_SUFFIXES = ", ".join(importlib.machinery.EXTENSION_SUFFIXES)
_ENGINE_CANDIDATE_TEXT = (
    "\n  - ".join(_ENGINE_CANDIDATES) if _ENGINE_CANDIDATES else "(none found)"
)
_ENGINE_SEARCHED_TEXT = "\n  - ".join(str(path) for path in _ENGINE_SEARCH_DIRS)

try:
    import aiterm_engine as native  # noqa: E402
except ModuleNotFoundError as exc:
    # Preserve the original exception (including its missing-module name) and
    # attach actionable context instead of replacing a loader/dependency error.
    if exc.name != "aiterm_engine":
        exc.add_note(
            "aiterm_engine was located, but importing it required another missing module. "
            f"Active Python: {sys.executable} ({sys.version.split()[0]})."
        )
        raise

    exc.add_note(
        "No native aiterm_engine module compatible with the active Python was found.\n"
        f"Python: {sys.executable}\n"
        f"Version: {sys.version.split()[0]}\n"
        f"Recognized extension suffixes: {_ENGINE_SUFFIXES}\n"
        f"Searched:\n  - {_ENGINE_SEARCHED_TEXT}\n"
        f"Built candidates:\n  - {_ENGINE_CANDIDATE_TEXT}\n"
        "Use the same Python installation for dependencies, CMake, and runtime; "
        "delete engine/build and rebuild with -DPython_EXECUTABLE set to that python.exe."
    )
    raise
except ImportError as exc:
    exc.add_note(
        "aiterm_engine was found but could not be loaded.\n"
        f"Python: {sys.executable}\n"
        f"Version: {sys.version.split()[0]}\n"
        f"Recognized extension suffixes: {_ENGINE_SUFFIXES}\n"
        f"Built candidates:\n  - {_ENGINE_CANDIDATE_TEXT}\n"
        "Rebuild the Release target with this exact Python and ensure its runtime DLL is available."
    )
    raise

_classifier = native.RiskClassifier()
_execution_id_counter = itertools.count(1)


def classify_command(command: str):
    return _classifier.classify(command)


def risk_level_name(level) -> str:
    return str(level).split(".")[-1]


def run_command_sync(command: str, working_dir: str | None = None, timeout_seconds: int = 30):
    """Blocking execution via the native engine (PTY/ConPTY), started directly
    inside `working_dir` (passed to the OS process creation call, not a shell
    `cd` string - safer against injection and works identically on Windows)."""
    return native.PtySession.run(command, working_dir or "", None, timeout_seconds)


def new_execution_id() -> int:
    return next(_execution_id_counter)


def start_streaming_execution(execution_id: int, command: str, working_dir: str | None,
                               on_chunk, on_done, timeout_seconds: int = 180):
    """
    Starts a non-blocking execution. `on_chunk`/`on_done` are plain callables invoked
    from a background native thread; the caller (main.py) is responsible for hopping
    back onto the asyncio event loop if needed (see main.py's use of
    call_soon_threadsafe).
    """
    native.PtySession.start_async(
        execution_id, command, working_dir or "", on_chunk, on_done, timeout_seconds
    )


def kill_execution(execution_id: int) -> bool:
    return native.PtySession.kill_execution(execution_id)
