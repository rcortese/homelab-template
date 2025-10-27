"""Tests for the ``scripts/check_all.sh`` wrapper script."""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path


def _copy_check_all(tmp_dir: Path) -> Path:
    """Copy the real ``check_all.sh`` script to ``tmp_dir`` and return its path."""

    repo_root = Path(__file__).resolve().parents[1]
    src = repo_root / "scripts" / "check_all.sh"
    dest_dir = tmp_dir / "scripts"
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / "check_all.sh"
    shutil.copy(src, dest)
    dest.chmod(0o755)
    return dest


def _create_shell_stub(path: Path, log_file: Path, message: str, exit_code: int = 0) -> None:
    """Create an executable shell stub that logs its invocation."""

    content = f"""#!/usr/bin/env bash
set -euo pipefail
echo {message!r} >> {str(log_file)!r}
exit {exit_code}
"""
    path.write_text(content, encoding="utf-8")
    path.chmod(0o755)


def _create_python_stub(path: Path, log_file: Path, message: str, exit_code: int = 0) -> None:
    """Create an executable Python stub that logs its invocation."""

    lines = [
        "#!/usr/bin/env python3",
        "from pathlib import Path",
        f"log_path = Path({str(log_file)!r})",
        "with log_path.open('a', encoding='utf-8') as fh:",
        f"    fh.write({message!r})",
        "    fh.write('\\n')",
    ]
    if exit_code:
        lines.append(f"raise SystemExit({exit_code})")
    content = "\n".join(lines) + "\n"
    path.write_text(content, encoding="utf-8")
    path.chmod(0o755)


def _prepare_repo(
    tmp_path: Path,
    *,
    failing_env_sync: bool = False,
    failing_validate_compose: bool = False,
) -> tuple[Path, Path]:
    """Set up a temporary repository layout with stubbed scripts."""

    repo_dir = tmp_path / "repo"
    scripts_dir = repo_dir / "scripts"
    repo_dir.mkdir()
    scripts_dir.mkdir()

    log_file = repo_dir / "stub.log"

    check_all_path = _copy_check_all(repo_dir)

    _create_shell_stub(
        scripts_dir / "check_structure.sh",
        log_file,
        "check_structure",
    )

    _create_python_stub(
        scripts_dir / "check_env_sync.py",
        log_file,
        "check_env_sync",
        exit_code=1 if failing_env_sync else 0,
    )

    _create_shell_stub(
        scripts_dir / "validate_compose.sh",
        log_file,
        "validate_compose",
        exit_code=1 if failing_validate_compose else 0,
    )

    return check_all_path, log_file


def _run_check_all(check_all: Path, cwd: Path) -> subprocess.CompletedProcess[str]:
    """Execute the copied ``check_all.sh`` script and return the result."""

    return subprocess.run(
        [str(check_all)],
        cwd=cwd,
        check=False,
        text=True,
        capture_output=True,
    )


def test_check_all_invokes_scripts_in_order(tmp_path: Path) -> None:
    """The wrapper should call each underlying script and succeed."""

    check_all, log_file = _prepare_repo(tmp_path)
    result = _run_check_all(check_all, check_all.parent.parent)

    assert result.returncode == 0, result.stderr
    assert log_file.exists()
    assert log_file.read_text(encoding="utf-8").splitlines() == [
        "check_structure",
        "check_env_sync",
        "validate_compose",
    ]


def test_check_all_stops_on_first_failure(tmp_path: Path) -> None:
    """A failure in an intermediate script should abort the remaining steps."""

    check_all, log_file = _prepare_repo(tmp_path, failing_env_sync=True)
    repo_dir = check_all.parent.parent
    result = _run_check_all(check_all, repo_dir)

    assert result.returncode != 0
    assert log_file.exists()
    assert log_file.read_text(encoding="utf-8").splitlines() == [
        "check_structure",
        "check_env_sync",
    ]


def test_check_all_fails_when_validate_compose_fails(tmp_path: Path) -> None:
    """If ``validate_compose`` fails the wrapper should report failure."""

    check_all, log_file = _prepare_repo(
        tmp_path,
        failing_validate_compose=True,
    )
    repo_dir = check_all.parent.parent
    result = _run_check_all(check_all, repo_dir)

    assert result.returncode != 0
    assert log_file.exists()
    assert log_file.read_text(encoding="utf-8").splitlines() == [
        "check_structure",
        "check_env_sync",
        "validate_compose",
    ]
