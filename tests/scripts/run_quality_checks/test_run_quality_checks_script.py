"""Tests for the ``scripts/run_quality_checks.sh`` helper."""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path


def _copy_script(tmp_dir: Path) -> Path:
    """Copy the real ``run_quality_checks.sh`` script to ``tmp_dir``."""

    repo_root = Path(__file__).resolve().parents[3]
    src = repo_root / "scripts" / "run_quality_checks.sh"
    dest_dir = tmp_dir / "scripts"
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / "run_quality_checks.sh"
    shutil.copy(src, dest)
    dest.chmod(0o755)
    return dest


def _create_executable(
    path: Path,
    *,
    log_file: Path,
    exit_code: int = 0,
    stdout: str | None = None,
) -> None:
    """Create a generic executable that logs its invocation."""

    log_target = str(log_file)
    lines = [
        "#!/usr/bin/env bash",
        "set -euo pipefail",
        f"echo {path.name!r} >> {log_target!r}",
        f"for arg in \"$@\"; do echo \"$arg\" >> {log_target!r}; done",
    ]
    if stdout is not None:
        lines.extend([
            "cat <<'EOF'",
            stdout,
            "EOF",
        ])

    if exit_code:
        exit_line = f"exit {exit_code}"
    else:
        exit_line = "exit 0"

    lines.append(exit_line)
    content = "\n".join(lines) + "\n"
    path.write_text(content, encoding="utf-8")
    path.chmod(0o755)


def _prepare_repo(
    tmp_path: Path,
    *,
    python_exit: int = 0,
    shellcheck_exit: int = 0,
    shfmt_exit: int = 0,
    checkbashisms_exit: int = 0,
    shfmt_stdout: str | None = None,
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
    checkbashisms_stub = repo_dir / "checkbashisms"

    _create_executable(python_stub, log_file=log_file, exit_code=python_exit)
    _create_executable(shellcheck_stub, log_file=log_file, exit_code=shellcheck_exit)
    _create_executable(
        shfmt_stub,
        log_file=log_file,
        exit_code=shfmt_exit,
        stdout=shfmt_stdout,
    )
    _create_executable(
        checkbashisms_stub,
        log_file=log_file,
        exit_code=checkbashisms_exit,
    )

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


def _build_env(repo_dir: Path, **overrides: str) -> dict[str, str]:
    """Return an environment that exposes the stub executables."""

    env = os.environ.copy()
    env.update(
        {
            "PYTHON_BIN": str(repo_dir / "python"),
            "SHELLCHECK_BIN": str(repo_dir / "shellcheck"),
            "SHFMT_BIN": str(repo_dir / "shfmt"),
            "CHECKBASHISMS_BIN": str(repo_dir / "checkbashisms"),
            "PATH": f"{repo_dir}:{env['PATH']}",
        }
    )
    env.update(overrides)
    return env


def test_run_quality_checks_reports_usage_for_help(tmp_path: Path) -> None:
    """``--help`` should print usage information and exit successfully."""

    script, log_file, repo_dir = _prepare_repo(tmp_path)
    env = _build_env(repo_dir)

    result = _run_script(script, repo_dir, env, "--help")

    assert result.returncode == 0
    assert "Usage: scripts/run_quality_checks.sh [--no-lint]" in result.stdout
    assert not log_file.exists()


def test_run_quality_checks_reports_usage_for_unknown_args(tmp_path: Path) -> None:
    """Unknown arguments should error and display usage on stderr."""

    script, log_file, repo_dir = _prepare_repo(tmp_path)
    env = _build_env(repo_dir)

    result = _run_script(script, repo_dir, env, "--bogus")

    assert result.returncode == 1
    assert "Unknown argument: --bogus" in result.stderr
    assert "Usage: scripts/run_quality_checks.sh [--no-lint]" in result.stderr
    assert not log_file.exists()


def test_run_quality_checks_invokes_commands(tmp_path: Path) -> None:
    """The wrapper should call pytest first and run shfmt before shell linters."""

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
        "checkbashisms",
        str(repo_dir / "scripts" / "check_all.sh"),
        str(repo_dir / "scripts" / "run_quality_checks.sh"),
        str(repo_dir / "scripts" / "lib" / "helpers.sh"),
    ]


def test_run_quality_checks_uses_python_runtime_wrapper(tmp_path: Path) -> None:
    """The wrapper should defer to python_runtime__run when available."""

    script, log_file, repo_dir = _prepare_repo(tmp_path)
    python_runtime = repo_dir / "scripts" / "lib" / "python_runtime.sh"
    log_target = str(log_file)
    python_runtime.write_text(
        "\n".join(
            [
                "#!/usr/bin/env bash",
                "set -euo pipefail",
                "python_runtime__run() {",
                f"  echo python_runtime__run >> {log_target!r}",
                f"  for arg in \"$@\"; do echo \"$arg\" >> {log_target!r}; done",
                "}",
            ]
        )
        + "\n",
        encoding="utf-8",
    )

    env = _build_env(repo_dir)

    result = _run_script(script, repo_dir, env, "--no-lint")

    assert result.returncode == 0, result.stderr
    log_lines = log_file.read_text(encoding="utf-8").splitlines()
    assert log_lines == [
        "python_runtime__run",
        str(repo_dir),
        "",
        "--",
        "-m",
        "pytest",
    ]
    assert "python" not in log_lines


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


def test_run_quality_checks_fails_when_shfmt_emits_diffs(tmp_path: Path) -> None:
    """If shfmt reports pending formatting, the wrapper should fail early."""

    shfmt_output = "--- foo\n+++ foo (shfmt)\n@@"
    script, log_file, repo_dir = _prepare_repo(tmp_path, shfmt_stdout=shfmt_output)
    env = _build_env(repo_dir)

    result = _run_script(script, repo_dir, env)

    assert result.returncode == 1
    assert result.stdout.strip() == shfmt_output
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


def test_run_quality_checks_fails_when_checkbashisms_fails(tmp_path: Path) -> None:
    """If checkbashisms fails, the wrapper should propagate the failure after shellcheck."""

    script, log_file, repo_dir = _prepare_repo(tmp_path, checkbashisms_exit=1)
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
        "checkbashisms",
        str(repo_dir / "scripts" / "check_all.sh"),
        str(repo_dir / "scripts" / "run_quality_checks.sh"),
        str(repo_dir / "scripts" / "lib" / "helpers.sh"),
    ]


def test_run_quality_checks_reports_missing_linter(tmp_path: Path) -> None:
    """If a configured linter is missing, the wrapper should fail with a clear error."""

    script, log_file, repo_dir = _prepare_repo(tmp_path)
    env = _build_env(repo_dir, SHFMT_BIN=str(repo_dir / "missing-shfmt"))

    result = _run_script(script, repo_dir, env)

    assert result.returncode == 1
    assert "Error: dependency 'shfmt' not found" in result.stderr
    assert not log_file.exists()


def test_run_quality_checks_skips_shell_linters_when_disabled(tmp_path: Path) -> None:
    """``--no-lint`` should run pytest even if shell linters are unavailable."""

    script, log_file, repo_dir = _prepare_repo(tmp_path)

    # Remove the fake linter binaries to mimic an environment without them.
    for missing in ("shellcheck", "shfmt", "checkbashisms"):
        (repo_dir / missing).unlink()

    env = _build_env(repo_dir)

    result = _run_script(script, repo_dir, env, "--no-lint")

    assert result.returncode == 0, result.stderr
    assert log_file.read_text(encoding="utf-8").splitlines() == [
        "python",
        "-m",
        "pytest",
    ]
