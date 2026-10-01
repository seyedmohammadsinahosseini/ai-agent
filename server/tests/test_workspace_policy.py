from pathlib import Path

from app.workspace_policy import check_command_scope


def test_requires_existing_workspace(tmp_path: Path):
    assert not check_command_scope("Get-ChildItem", None).allowed
    assert not check_command_scope("Get-ChildItem", str(tmp_path / "missing")).allowed
    result = check_command_scope("Get-ChildItem", str(tmp_path))
    assert result.allowed
    assert result.normalized_working_dir == str(tmp_path.resolve())


def test_blocks_common_path_escapes(tmp_path: Path):
    commands = [
        "Get-Content ../secret.txt",
        "Get-Content /etc/passwd",
        r"Get-Content \\server\share\secret.txt",
        r"Get-Content $env:USERPROFILE\secret.txt",
        r"Get-Content ~\secret.txt",
    ]
    for command in commands:
        assert not check_command_scope(command, str(tmp_path)).allowed, command


def test_multiline_is_build_only_and_nul_is_always_blocked(tmp_path: Path):
    script = "Set-Content index.html '<h1>Hello</h1>'\nSet-Content app.js 'ready'"
    assert not check_command_scope(script, str(tmp_path)).allowed
    assert check_command_scope(script, str(tmp_path), allow_multiline=True).allowed
    assert not check_command_scope(
        "Set-Content index.html ok\nGet-Content ../secret.txt",
        str(tmp_path),
        allow_multiline=True,
    ).allowed
    assert not check_command_scope(
        "Set-Content index.html ok\x00hidden",
        str(tmp_path),
        allow_multiline=True,
    ).allowed


def test_allows_relative_paths_and_urls(tmp_path: Path):
    assert check_command_scope("Get-Content notes.txt", str(tmp_path)).allowed
    assert check_command_scope("curl https://example.com/file -o file", str(tmp_path)).allowed
