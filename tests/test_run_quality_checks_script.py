"""Tests for the ``scripts/run_quality_checks.sh`` helper."""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path


def _copy_script(tmp_dir: Path) -> Path:
    """Copy the real ``run_quality_checks.sh`` script to ``tmp_dir``."""

    repo_root = Path(__file__).resolve().parents[1]
    src = repo_root / "scripts" / "run_quality_checks.sh"
    dest_dir = tmp_dir / "scripts"
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / "run_quality_checks.sh"
    shutil.copy(src, dest)
    dest.chmod(0o755)
    return dest


def _create_executable(path: Path, *, log_file: Path, exit_code: int = 0) -> None:
    """Create a generic executable that logs its invocation."""

    log_target = str(log_file)
    lines = [
        "#!/usr/bin/env bash",
        "set -euo pipefail",
        f"echo {path.name!r} >> {log_target!r}",
        f"for arg in \"$@\"; do echo \"$arg\" >> {log_target!r}; done",
    ]
    if exit_code:
        lines.append(f"exit {exit_code}")
    else:
        lines.append("exit 0")
    content = "\n".join(lines) + "\n"
    path.write_text(content, encoding="utf-8")
    path.chmod(0o755)


def _prepare_repo(
    tmp_path: Path,
    *,
    python_exit: int = 0,
    shellcheck_exit: int = 0,
    shfmt_exit: int = 0,
) -> tuple[Path, Path, Path]:
    """Set up a temporary repository with stubbed executables."""

    repo_dir = tmp_path / "repo"
    scripts_dir = repo_dir / "scripts"
    lib_dir = scripts_dir / "lib"
    repo_dir.mkdir()
    scripts_dir.mkdir()
    lib_dir.mkdir()

    log_file = repo_dir / "invocations.log"

    script_path = _copy_script(repo_dir)

    python_stub = repo_dir / "python"
    shellcheck_stub = repo_dir / "shellcheck"
    shfmt_stub = repo_dir / "shfmt"

    _create_executable(python_stub, log_file=log_file, exit_code=python_exit)
    _create_executable(shellcheck_stub, log_file=log_file, exit_code=shellcheck_exit)
    _create_executable(shfmt_stub, log_file=log_file, exit_code=shfmt_exit)

    # Create dummy shell scripts so the wrapper has something to lint.
    (scripts_dir / "check_all.sh").write_text(
        "#!/usr/bin/env bash\nexit 0\n",
        encoding="utf-8",
    )
    (lib_dir / "helpers.sh").write_text(
        "#!/usr/bin/env bash\nexit 0\n",
        encoding="utf-8",
    )

    return script_path, log_file, repo_dir


def _run_script(
    script: Path,
    cwd: Path,
    env: dict[str, str],
    *args: str,
) -> subprocess.CompletedProcess[str]:
    """Execute the copied helper script with a custom environment."""

    return subprocess.run(
        [str(script), *args],
        cwd=cwd,
        env=env,
        check=False,
        text=True,
        capture_output=True,
    )


def _build_env(repo_dir: Path) -> dict[str, str]:
    """Return an environment that exposes the stub executables."""

    env = os.environ.copy()
    env.update(
        {
            "PYTHON_BIN": str(repo_dir / "python"),
            "SHELLCHECK_BIN": str(repo_dir / "shellcheck"),
            "SHFMT_BIN": str(repo_dir / "shfmt"),
            "PATH": f"{repo_dir}:{env['PATH']}",
        }
    )
    return env


def test_run_quality_checks_invokes_commands(tmp_path: Path) -> None:
    """The wrapper should call pytest first and run shfmt before shellcheck."""

    script, log_file, repo_dir = _prepare_repo(tmp_path)
    env = _build_env(repo_dir)

    result = _run_script(script, repo_dir, env)

    assert result.returncode == 0, result.stderr
    assert log_file.read_text(encoding="utf-8").splitlines() == [
        "python",
        "-m",
        "pytest",
        "shfmt",
        "-d",
        str(repo_dir / "scripts" / "check_all.sh"),
        str(repo_dir / "scripts" / "run_quality_checks.sh"),
        str(repo_dir / "scripts" / "lib" / "helpers.sh"),
        "shellcheck",
        str(repo_dir / "scripts" / "check_all.sh"),
        str(repo_dir / "scripts" / "run_quality_checks.sh"),
        str(repo_dir / "scripts" / "lib" / "helpers.sh"),
    ]


def test_run_quality_checks_stops_after_failed_pytest(tmp_path: Path) -> None:
    """If pytest fails, shellcheck should not run."""

    script, log_file, repo_dir = _prepare_repo(tmp_path, python_exit=1)
    env = _build_env(repo_dir)

    result = _run_script(script, repo_dir, env)

    assert result.returncode != 0
    assert log_file.read_text(encoding="utf-8").splitlines() == [
        "python",
        "-m",
        "pytest",
    ]


def test_run_quality_checks_fails_when_shellcheck_fails(tmp_path: Path) -> None:
    """If shellcheck fails, the wrapper should propagate the failure after shfmt."""

    script, log_file, repo_dir = _prepare_repo(tmp_path, shellcheck_exit=1)
    env = _build_env(repo_dir)

    result = _run_script(script, repo_dir, env)

    assert result.returncode == 1
    assert log_file.read_text(encoding="utf-8").splitlines() == [
        "python",
        "-m",
        "pytest",
        "shfmt",
        "-d",
        str(repo_dir / "scripts" / "check_all.sh"),
        str(repo_dir / "scripts" / "run_quality_checks.sh"),
        str(repo_dir / "scripts" / "lib" / "helpers.sh"),
        "shellcheck",
        str(repo_dir / "scripts" / "check_all.sh"),
        str(repo_dir / "scripts" / "run_quality_checks.sh"),
        str(repo_dir / "scripts" / "lib" / "helpers.sh"),
    ]


def test_run_quality_checks_fails_when_shfmt_fails(tmp_path: Path) -> None:
    """If shfmt fails, the wrapper should fail before running shellcheck."""

    script, log_file, repo_dir = _prepare_repo(tmp_path, shfmt_exit=1)
    env = _build_env(repo_dir)

    result = _run_script(script, repo_dir, env)

    assert result.returncode == 1
    assert log_file.read_text(encoding="utf-8").splitlines() == [
        "python",
        "-m",
        "pytest",
        "shfmt",
        "-d",
        str(repo_dir / "scripts" / "check_all.sh"),
        str(repo_dir / "scripts" / "run_quality_checks.sh"),
        str(repo_dir / "scripts" / "lib" / "helpers.sh"),
    ]


def test_run_quality_checks_skips_shellcheck_when_disabled(tmp_path: Path) -> None:
    """Passing ``--no-lint`` should prevent shfmt and shellcheck from running."""

    script, log_file, repo_dir = _prepare_repo(tmp_path)
    env = _build_env(repo_dir)

    result = _run_script(script, repo_dir, env, "--no-lint")

    assert result.returncode == 0, result.stderr
    assert log_file.read_text(encoding="utf-8").splitlines() == [
        "python",
        "-m",
        "pytest",
    ]
