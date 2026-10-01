from pathlib import Path

from app import uploads


def test_filename_sanitization_blocks_traversal_devices_and_long_names():
    assert uploads.sanitize_filename("../../evil.txt") == "evil.txt"
    assert uploads.sanitize_filename(r"..\evil.txt") == ".._evil.txt"
    assert uploads.sanitize_filename("..") not in (".", "..")
    assert uploads.sanitize_filename("CON.txt").startswith("_")
    assert len(uploads.sanitize_filename("a" * 300 + ".txt")) <= 180


def test_context_upload_can_be_discarded():
    stored = uploads.save_context_upload("context.txt", b"temporary")
    path = Path(stored.saved_path)
    assert path.exists()
    assert uploads.delete_context_upload(stored.id)
    assert not path.exists()
    assert not uploads.delete_context_upload(stored.id)


def test_workspace_upload_does_not_overwrite(tmp_path: Path):
    (tmp_path / "notes.txt").write_text("original")
    stored = uploads.save_workspace_upload("notes.txt", b"new", str(tmp_path))
    assert stored.filename == "notes_1.txt"
    assert (tmp_path / "notes.txt").read_text() == "original"
    assert (tmp_path / "notes_1.txt").read_bytes() == b"new"
