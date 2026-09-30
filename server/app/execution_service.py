"""
Shared authorization logic used by both the plain REST /execute endpoint and
the streaming /ws/execute endpoint, so the two code paths can never drift
apart in terms of safety rules.

Three independent layers are checked, in order:
  1) Plan/Build mode policy (mode_policy.py)      - conservative allowlist
  2) Deterministic risk classification (C++ engine) - destructiveness level
  3) Explicit user confirmation state              - what the client asserts
"""
from dataclasses import dataclass
from typing import Optional

from . import engine_bridge
from . import mode_policy

DANGEROUS_CONFIRMATION_PHRASE = "I understand, run it"


@dataclass
class AuthorizationResult:
    allowed: bool
    risk_level: str
    risk_human_reason: str
    message: Optional[str] = None


def authorize(command: str, mode: str, user_confirmed: bool,
              confirmation_phrase: Optional[str]) -> AuthorizationResult:
    # Layer 1: Plan mode never allows state-changing commands, period.
    if mode == "plan":
        ok, reason = mode_policy.plan_mode_allows(command)
        if not ok:
            return AuthorizationResult(False, "BLOCKED_BY_MODE", reason, reason)

    # Layer 2: deterministic risk classification
    classification = engine_bridge.classify_command(command)
    level = engine_bridge.risk_level_name(classification.level)

    if level == "BLOCKED":
        return AuthorizationResult(
            False, level, classification.human_reason,
            "This command is in the permanently blocked category and will never run.",
        )

    if level in ("CONFIRM", "DANGEROUS") and not user_confirmed:
        return AuthorizationResult(
            False, level, classification.human_reason, "This command requires your confirmation.",
        )

    if level == "DANGEROUS":
        if confirmation_phrase != DANGEROUS_CONFIRMATION_PHRASE:
            return AuthorizationResult(
                False, level, classification.human_reason,
                f'To run this dangerous command, type the phrase "{DANGEROUS_CONFIRMATION_PHRASE}" exactly.',
            )

    return AuthorizationResult(True, level, classification.human_reason)
