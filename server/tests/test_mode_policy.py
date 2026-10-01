from app.mode_policy import is_read_only_command, plan_mode_allows


def test_allows_single_known_read_only_commands():
    assert is_read_only_command("Get-ChildItem")
    assert is_read_only_command("Get-Content notes.txt")
    assert is_read_only_command("git status")
    assert is_read_only_command('powershell -NoProfile -Command "Get-ChildItem"')


def test_blocks_redirection_chaining_and_substitution():
    blocked = [
        "echo hello > changed.txt",
        "Get-ChildItem; Remove-Item changed.txt",
        "Get-ChildItem | Remove-Item",
        "ls && rm changed.txt",
        "cat $(touch changed.txt)",
        "Get-Content (Remove-Item changed.txt)",
        "Get-Content $env:USERPROFILE\\secret.txt",
    ]
    for command in blocked:
        allowed, reason = plan_mode_allows(command)
        assert not allowed, command
        assert "Plan mode" in reason


def test_blocks_mixed_behavior_or_unknown_commands():
    assert not is_read_only_command("date 01-01-2030")
    assert not is_read_only_command("find . -delete")
    assert not is_read_only_command("python script.py")
    assert not is_read_only_command("")
