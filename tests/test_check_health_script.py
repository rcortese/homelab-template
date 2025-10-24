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


def test_invokes_ps_and_logs_with_custom_files(docker_stub: DockerStub) -> None:
    env = {
        "COMPOSE_FILES": "compose/base.yml compose/extra.yml",
        "COMPOSE_ENV_FILE": "env/custom.env",
    }

    result = run_check_health(env=env)

    assert result.returncode == 0, result.stderr

    calls = docker_stub.read_calls()
    assert calls == [
        [
            "compose",
            "--env-file",
            "env/custom.env",
            "-f",
            "compose/base.yml",
            "-f",
            "compose/extra.yml",
            "ps",
        ],
        [
            "compose",
            "--env-file",
            "env/custom.env",
            "-f",
            "compose/base.yml",
            "-f",
            "compose/extra.yml",
            "logs",
            "--tail=50",
            "app",
        ],
    ]


def test_respects_docker_compose_bin_override(docker_stub: DockerStub) -> None:
    env = {"DOCKER_COMPOSE_BIN": "docker --context remote compose"}

    result = run_check_health(env=env)

    assert result.returncode == 0, result.stderr

    calls = docker_stub.read_calls()
    assert calls == [
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
    stub_dir = Path(os.environ["PATH"].split(os.pathsep)[0])
    stub_script = stub_dir / "docker"
    stub_script.write_text(
        """#!/usr/bin/env python3
import json
import os
import pathlib
import sys

log_path = pathlib.Path(os.environ["DOCKER_STUB_LOG"])
with log_path.open("a", encoding="utf-8") as handle:
    json.dump(sys.argv[1:], handle)
    handle.write("\\n")

exit_code_file = os.environ.get("DOCKER_STUB_EXIT_CODE_FILE")
base_exit_code = 0
if exit_code_file:
    try:
        base_exit_code = int(pathlib.Path(exit_code_file).read_text().strip() or "0")
    except FileNotFoundError:
        base_exit_code = 0

exit_code = base_exit_code
fail_targets = [
    entry.strip()
    for entry in os.environ.get("DOCKER_STUB_FAIL_ONCE_FOR", "").split(",")
    if entry.strip()
]
state_file = os.environ.get("DOCKER_STUB_FAIL_ONCE_STATE")
if fail_targets and state_file:
    args = sys.argv[1:]
    service = args[-1] if "logs" in args else None
    if service and service in fail_targets:
        state_path = pathlib.Path(state_file)
        if state_path.exists():
            already = {entry for entry in state_path.read_text().split(",") if entry}
        else:
            already = set()
        if service not in already:
            already.add(service)
            state_path.write_text(",".join(sorted(already)), encoding="utf-8")
            exit_code = 1
        else:
            exit_code = base_exit_code

sys.exit(exit_code)
""",
        encoding="utf-8",
    )
    stub_script.chmod(0o755)

    state_file = tmp_path / "fail_once_state"
    monkeypatch.setenv("HEALTH_SERVICES", "app app-core app-media")
    monkeypatch.setenv("DOCKER_STUB_FAIL_ONCE_FOR", "app,app-core")
    monkeypatch.setenv("DOCKER_STUB_FAIL_ONCE_STATE", str(state_file))

    result = run_check_health()

    assert result.returncode == 0, result.stderr

    calls = docker_stub.read_calls()
    assert calls == [
        ["compose", "ps"],
        ["compose", "logs", "--tail=50", "app"],
        ["compose", "logs", "--tail=50", "app-core"],
        ["compose", "logs", "--tail=50", "app-media"],
    ]


def test_logs_reports_failure_when_all_services_fail(docker_stub: DockerStub) -> None:
    stub_dir = Path(os.environ["PATH"].split(os.pathsep)[0])
    stub_script = stub_dir / "docker"
    stub_script.write_text(
        """#!/usr/bin/env python3
import json
import os
import pathlib
import sys

log_path = pathlib.Path(os.environ["DOCKER_STUB_LOG"])
with log_path.open("a", encoding="utf-8") as handle:
    json.dump(sys.argv[1:], handle)
    handle.write("\\n")

args = sys.argv[1:]
if "logs" in args:
    sys.exit(1)

sys.exit(0)
""",
        encoding="utf-8",
    )
    stub_script.chmod(0o755)

    result = run_check_health(env={"HEALTH_SERVICES": "app app-core app-media"})

    assert result.returncode != 0
    assert "Failed to retrieve logs for services" in result.stderr

    calls = docker_stub.read_calls()
    assert calls == [
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
    assert calls == [
        [
            "compose",
            "--env-file",
            env_file,
            "-f",
            "compose/base.yml",
            "-f",
            "compose/core.yml",
            "ps",
        ],
        [
            "compose",
            "--env-file",
            env_file,
            "-f",
            "compose/base.yml",
            "-f",
            "compose/core.yml",
            "logs",
            "--tail=50",
            "app-core",
        ],
    ]
