"""
Bridge to the native C++ engine (aiterm_engine.so on Linux/macOS,
aiterm_engine.pyd on Windows).

In the final Windows build, this native module ships alongside the main
executable. Here we add the build directory to sys.path so the import works
during development.
"""
import sys
import itertools
from pathlib import Path

_ENGINE_BUILD_DIR = Path(__file__).resolve().parents[2] / "engine" / "build"
if str(_ENGINE_BUILD_DIR) not in sys.path:
    sys.path.insert(0, str(_ENGINE_BUILD_DIR))
# Windows CMake/MSVC builds typically place the .pyd under a config subfolder
# (e.g. build/Release/aiterm_engine.pyd) rather than directly in build/.
for _sub in ("Release", "RelWithDebInfo", "Debug"):
    _p = _ENGINE_BUILD_DIR / _sub
    if _p.exists() and str(_p) not in sys.path:
        sys.path.insert(0, str(_p))

import aiterm_engine as native  # noqa: E402

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
