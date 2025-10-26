from __future__ import annotations

import os
import subprocess
from pathlib import Path
from typing import TYPE_CHECKING

import pytest

if TYPE_CHECKING:
    from .conftest import DockerStub


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = REPO_ROOT / "scripts" / "check_health.sh"


def run_check_health(
    args: list[str] | None = None,
    env: dict[str, str] | None = None,
    cwd: Path | None = None,
    script_path: Path | None = None,
) -> subprocess.CompletedProcess[str]:
    command = [str(script_path or SCRIPT_PATH)]
    if args:
        command.extend(args)
    return subprocess.run(
        command,
        capture_output=True,
        text=True,
        check=False,
        cwd=cwd or REPO_ROOT,
        env={**os.environ, **(env or {})},
    )


def _expected_compose_call(env_file: str | None, files: list[str], *args: str) -> list[str]:
    cmd = ["compose"]
    if env_file:
        cmd.extend(["--env-file", env_file])
    for path in files:
        cmd.extend(["-f", path])
    cmd.extend(args)
    return cmd


def test_invokes_ps_and_logs_with_custom_files(docker_stub: DockerStub) -> None:
    env = {
        "COMPOSE_FILES": "compose/base.yml compose/extra.yml",
        "COMPOSE_ENV_FILE": "env/custom.env",
    }

    result = run_check_health(env=env)

    assert result.returncode == 0, result.stderr

    calls = docker_stub.read_calls()
    assert calls == [
        _expected_compose_call("env/custom.env", ["compose/base.yml", "compose/extra.yml"], "config", "--services"),
        _expected_compose_call("env/custom.env", ["compose/base.yml", "compose/extra.yml"], "ps"),
        _expected_compose_call("env/custom.env", ["compose/base.yml", "compose/extra.yml"], "logs", "--tail=50", "app"),
    ]


def test_loads_compose_extra_files_from_env_file(
    docker_stub: DockerStub, tmp_path: Path
) -> None:
    env_file = tmp_path / "custom.env"
    env_file.write_text(
        "COMPOSE_EXTRA_FILES=compose/overlays/extra.yml\n"
        "SERVICE_NAME=app-extra\n",
        encoding="utf-8",
    )

    env = {
        "COMPOSE_FILES": "compose/base.yml",
        "COMPOSE_ENV_FILE": str(env_file),
    }

    result = run_check_health(env=env)

    assert result.returncode == 0, result.stderr

    expected_files = ["compose/base.yml", "compose/overlays/extra.yml"]
    calls = docker_stub.read_calls()
    assert calls == [
        _expected_compose_call(str(env_file), expected_files, "config", "--services"),
        _expected_compose_call(str(env_file), expected_files, "ps"),
        _expected_compose_call(str(env_file), expected_files, "logs", "--tail=50", "app-extra"),
    ]


def test_respects_docker_compose_bin_override(docker_stub: DockerStub) -> None:
    env = {"DOCKER_COMPOSE_BIN": "docker --context remote compose"}

    result = run_check_health(env=env)

    assert result.returncode == 0, result.stderr

    calls = docker_stub.read_calls()
    assert calls == [
        ["--context", "remote", "compose", "config", "--services"],
        ["--context", "remote", "compose", "ps"],
        ["--context", "remote", "compose", "logs", "--tail=50", "app"],
    ]


@pytest.mark.parametrize("arg", ["-h", "--help"])
def test_help_flags_exit_early_and_show_usage(
    docker_stub: DockerStub, arg: str
) -> None:
    result = run_check_health(args=[arg])

    assert result.returncode == 0, result.stderr
    assert "Uso: scripts/check_health.sh" in result.stdout

    calls = docker_stub.read_calls()
    assert calls == []


def test_logs_fallback_through_alternative_services(
    docker_stub: DockerStub,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    state_file = tmp_path / "fail_once_state"
    docker_stub.reset_fail_once_state()
    if state_file.exists():
        state_file.unlink()
    monkeypatch.setenv("HEALTH_SERVICES", "app-core")
    monkeypatch.setenv("DOCKER_STUB_FAIL_ONCE_FOR", "app-core")
    monkeypatch.setenv("DOCKER_STUB_FAIL_ONCE_STATE", str(state_file))

    result = run_check_health()

    assert result.returncode == 0, result.stderr

    calls = docker_stub.read_calls()
    assert calls == [
        ["compose", "config", "--services"],
        ["compose", "ps"],
        ["compose", "logs", "--tail=50", "app-core"],
        ["compose", "logs", "--tail=50", "app"],
    ]


def test_logs_reports_failure_when_all_services_fail(
    docker_stub: DockerStub, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("DOCKER_STUB_ALWAYS_FAIL_LOGS", "1")

    result = run_check_health(env={"HEALTH_SERVICES": "app app-core app-media"})

    assert result.returncode != 0
    assert "Failed to retrieve logs for services" in result.stderr

    calls = docker_stub.read_calls()
    assert calls == [
        ["compose", "config", "--services"],
        ["compose", "ps"],
        ["compose", "logs", "--tail=50", "app"],
        ["compose", "logs", "--tail=50", "app-core"],
        ["compose", "logs", "--tail=50", "app-media"],
    ]


def test_infers_compose_files_and_env_from_instance(
    docker_stub: DockerStub, repo_copy: Path
) -> None:
    script_path = repo_copy / "scripts" / "check_health.sh"

    result = run_check_health(
        args=["core"],
        cwd=repo_copy,
        script_path=script_path,
    )

    assert result.returncode == 0, result.stderr

    calls = docker_stub.read_calls()
    env_file = str(repo_copy / "env" / "local" / "core.env")
    expected_files = [
        "compose/base.yml",
        "compose/apps/app/base.yml",
        "compose/apps/app/core.yml",
    ]
    assert calls == [
        _expected_compose_call(env_file, expected_files, "config", "--services"),
        _expected_compose_call(env_file, expected_files, "ps"),
        _expected_compose_call(env_file, expected_files, "logs", "--tail=50", "app-core"),
    ]
