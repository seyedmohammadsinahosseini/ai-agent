"""Shared command authorization for REST, chat auto-run and WebSockets.

Checks are intentionally repeated immediately before execution:
  1) selected-workspace validation and obvious path-escape prevention
  2) Plan-mode read-only policy
  3) deterministic native risk classification
  4) explicit confirmation requirements
"""
from dataclasses import dataclass
from typing import Optional

from . import engine_bridge
from . import mode_policy
from . import workspace_policy

DANGEROUS_CONFIRMATION_PHRASE = "I understand, run it"


@dataclass
class AuthorizationResult:
    allowed: bool
    risk_level: str
    risk_human_reason: str
    message: Optional[str] = None
    normalized_working_dir: Optional[str] = None


def authorize(command: str, mode: str, user_confirmed: bool,
              confirmation_phrase: Optional[str],
              working_dir: Optional[str] = None) -> AuthorizationResult:
    # Layer 1: every command starts in a real, validated workspace and cannot
    # explicitly reference common path escapes. This is still not an OS-level
    # sandbox; see workspace_policy.py and the UI/docs wording.
    scope = workspace_policy.check_command_scope(
        command, working_dir, require_writable=(mode == "build")
    )
    if not scope.allowed:
        return AuthorizationResult(
            False, "BLOCKED_BY_WORKSPACE", scope.message, scope.message,
            normalized_working_dir=scope.normalized_working_dir,
        )

    # Layer 2: Plan mode only permits a single known read-only command.
    if mode == "plan":
        ok, reason = mode_policy.plan_mode_allows(command)
        if not ok:
            return AuthorizationResult(
                False, "BLOCKED_BY_MODE", reason, reason,
                normalized_working_dir=scope.normalized_working_dir,
            )

    # Layer 3: deterministic native risk classification. Unknown commands are
    # no longer SAFE; the classifier defaults them to CONFIRM.
    classification = engine_bridge.classify_command(command)
    level = engine_bridge.risk_level_name(classification.level)

    if level == "BLOCKED":
        return AuthorizationResult(
            False, level, classification.human_reason,
            "This command is in the permanently blocked category and will never run.",
            normalized_working_dir=scope.normalized_working_dir,
        )

    if level in ("CONFIRM", "DANGEROUS") and not user_confirmed:
        return AuthorizationResult(
            False, level, classification.human_reason, "This command requires your confirmation.",
            normalized_working_dir=scope.normalized_working_dir,
        )

    if level == "DANGEROUS" and confirmation_phrase != DANGEROUS_CONFIRMATION_PHRASE:
        return AuthorizationResult(
            False, level, classification.human_reason,
            f'To run this dangerous command, type the phrase "{DANGEROUS_CONFIRMATION_PHRASE}" exactly.',
            normalized_working_dir=scope.normalized_working_dir,
        )

    return AuthorizationResult(
        True, level, classification.human_reason,
        normalized_working_dir=scope.normalized_working_dir,
    )
