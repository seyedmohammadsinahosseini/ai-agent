"""
Plan vs Build mode enforcement.

This is a THIRD independent safety layer on top of:
  1) the AI model's own instructions (system prompt, see ai_providers.py)
  2) the deterministic C++ RiskClassifier (destructiveness level)

Plan mode must never allow state-changing commands to run, no matter what the
AI suggested or how the risk classifier scored it. We do this with a small,
conservative allowlist of read-only command prefixes. Anything not matching
this allowlist is rejected in Plan mode, even if the risk classifier would
otherwise call it SAFE.
"""
import re

_READ_ONLY_PATTERNS = [
    r"^ls\b", r"^dir\b", r"^cat\b", r"^type\b", r"^more\b",
    r"^pwd\b", r"^cd\b\s*$",  # bare `cd` (print/no-op) - not `cd X && ...`
    r"^echo\b", r"^find\b", r"^grep\b", r"^tree\b",
    r"^whoami\b", r"^hostname\b", r"^date\b", r"^time\b",
    r"^get-childitem\b", r"^get-content\b", r"^get-item\b",
    r"^get-process\b", r"^get-service\b", r"^get-location\b",
    r"^get-date\b", r"^select-string\b", r"^measure-object\b",
    r"^wc\b", r"^head\b", r"^tail\b", r"^du\b", r"^df\b",
    r"^ping\b", r"^tracert\b", r"^nslookup\b",
]
_READ_ONLY_REGEXES = [re.compile(p, re.IGNORECASE) for p in _READ_ONLY_PATTERNS]

# Even in Plan mode, a command must not contain these regardless of its prefix
# (defends against something like "ls; rm -rf /" chaining).
_CHAIN_OPERATORS = re.compile(r"(&&|\|\||;|\|(?!\|))")


def is_read_only_command(command: str) -> bool:
    normalized = command.strip()
    if not normalized:
        return True
    if _CHAIN_OPERATORS.search(normalized):
        return False
    return any(rx.search(normalized) for rx in _READ_ONLY_REGEXES)


def plan_mode_allows(command: str) -> tuple[bool, str]:
    if is_read_only_command(command):
        return True, ""
    return False, ("This command changes something on your system. Plan mode is read-only - "
                    "switch to Build mode to let the agent execute it.")
