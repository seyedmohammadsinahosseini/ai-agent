import os
import sys
from pathlib import Path

# Make `app` importable when pytest is launched from the repository root.
SERVER_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVER_DIR))

# Never let tests touch the user's real AI Terminal state.
os.environ.setdefault("AITERM_HOME", str(SERVER_DIR / ".test-state"))
