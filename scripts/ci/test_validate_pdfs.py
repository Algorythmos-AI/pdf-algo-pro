"""Tests for validate_pdfs.sh, with a stand-in qpdf that replays what the real one printed.

    uv run --with pytest==8.4.2 pytest -q scripts/ci
"""
from __future__ import annotations

import os
import stat
import subprocess
from pathlib import Path

SCRIPT = Path(__file__).resolve().with_name("validate_pdfs.sh")
ALLOWED = Path(__file__).resolve().with_name("qpdf_allowed_warnings.txt")
OFFSET_ZERO = "object has offset 0 - a common error handled correctly by qpdf and most other applications"

# What qpdf 12.4.2 printed for each file name, and its exit status (issue #96 for the warnings).
FAKE_QPDF = """#!/usr/bin/env python3
import os, sys
name = os.path.basename(sys.argv[-1])
if name.startswith("clean"):
    print("checking " + name); sys.exit(0)
if name.startswith("broken"):
    print("qpdf: " + name + ": not a PDF file", file=sys.stderr); sys.exit(2)
if name == "right-to-left-and-CJK.pdf" or name.startswith("offset-zero"):
    for obj in (6, 9, 18):
        print(f"WARNING: saved/{name} (object {obj} 0): %s" % ("OFFSET_ZERO",))
    print("qpdf: operation succeeded with warnings"); sys.exit(3)
if name.startswith("mixed"):
    print(f"WARNING: saved/{name} (object 6 0): OFFSET_ZERO")
    print(f"WARNING: saved/{name}: file is damaged")
    print("qpdf: operation succeeded with warnings"); sys.exit(3)
sys.exit(2)
""".replace("OFFSET_ZERO", OFFSET_ZERO)


def run(tmp_path: Path, names: list[str], allowed: Path | None = None) -> subprocess.CompletedProcess:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir(exist_ok=True)
    qpdf = bin_dir / "qpdf"
    qpdf.write_text(FAKE_QPDF)
    qpdf.chmod(qpdf.stat().st_mode | stat.S_IEXEC)
    saved = tmp_path / "saved"
    saved.mkdir(exist_ok=True)
    for name in names:
        (saved / name).write_bytes(b"%PDF-1.7\n")
    env = {**os.environ, "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}"}
    args = ["bash", str(SCRIPT), str(saved)] + ([str(allowed)] if allowed else [])
    return subprocess.run(args, capture_output=True, text=True, env=env)


def test_clean_files_pass(tmp_path):
    result = run(tmp_path, ["clean-a.pdf", "clean-b.pdf"])
    assert result.returncode == 0, result.stdout
    assert "ok       clean-a.pdf" in result.stdout


def test_errors_fail(tmp_path):
    result = run(tmp_path, ["clean.pdf", "broken.pdf"])
    assert result.returncode == 1
    assert "::error title=qpdf errors::broken.pdf" in result.stdout


def test_the_documented_warning_of_issue_96_is_allowed_for_its_file_only(tmp_path):
    result = run(tmp_path, ["right-to-left-and-CJK.pdf", "clean.pdf"])
    assert result.returncode == 0, result.stdout
    assert "::notice title=qpdf allowed warnings::right-to-left-and-CJK.pdf (3 allowed" in result.stdout
    # The same warning in any other file fails: the allowance is for one named synthetic file.
    (tmp_path / "other").mkdir()
    other = run(tmp_path / "other", ["offset-zero-elsewhere.pdf"])
    assert other.returncode == 1
    assert "::error title=qpdf warnings::offset-zero-elsewhere.pdf" in other.stdout


def test_an_allowed_warning_does_not_hide_another(tmp_path):
    allowed = tmp_path / "allowed.txt"
    allowed.write_text(f"# comment\nmixed.pdf|{OFFSET_ZERO}\n")
    result = run(tmp_path, ["mixed.pdf"], allowed)
    assert result.returncode == 1
    assert "file is damaged" in result.stdout and OFFSET_ZERO not in result.stdout.split("::error")[1]


def test_without_an_allowed_list_every_warning_fails(tmp_path):
    result = run(tmp_path, ["right-to-left-and-CJK.pdf"], tmp_path / "missing.txt")
    assert result.returncode == 1


def test_an_empty_folder_fails(tmp_path):
    result = run(tmp_path, [])
    assert result.returncode == 1 and "No PDFs to check" in result.stdout


def test_the_allowed_list_names_its_issue_for_every_entry():
    lines = ALLOWED.read_text().splitlines()
    entries = [line for line in lines if line.strip() and not line.lstrip().startswith("#")]
    assert entries == [f"right-to-left-and-CJK.pdf|{OFFSET_ZERO}"]
    assert any("#96" in line for line in lines if line.startswith("#"))
