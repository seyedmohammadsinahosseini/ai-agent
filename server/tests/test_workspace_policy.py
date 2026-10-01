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
        "Get-Content first.txt\nGet-Content second.txt",
    ]
    for command in commands:
        assert not check_command_scope(command, str(tmp_path)).allowed, command


def test_allows_relative_paths_and_urls(tmp_path: Path):
    assert check_command_scope("Get-Content notes.txt", str(tmp_path)).allowed
    assert check_command_scope("curl https://example.com/file -o file", str(tmp_path)).allowed
