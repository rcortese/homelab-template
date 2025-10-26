from __future__ import annotations

import pytest
from pathlib import Path

from tests.conftest import DockerStub

from .utils import run_check_health


def test_logs_fallback_through_alternative_services(
    docker_stub: DockerStub, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
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


def test_logs_handles_comma_separated_health_services(docker_stub: DockerStub) -> None:
    env = {
        "HEALTH_SERVICES": "app-core,app-extra",
        "DOCKER_STUB_FAIL_ALWAYS_FOR": "app-core",
    }

    result = run_check_health(env=env)

    assert result.returncode == 0, result.stderr
    assert "Warning: Failed to retrieve logs for services: app-core" in result.stderr

    calls = docker_stub.read_calls()
    assert calls == [
        ["compose", "config", "--services"],
        ["compose", "ps"],
        ["compose", "logs", "--tail=50", "app-core"],
        ["compose", "logs", "--tail=50", "app-extra"],
        ["compose", "logs", "--tail=50", "app"],
    ]


def test_logs_attempts_all_services_even_after_success(docker_stub: DockerStub) -> None:
    env = {"HEALTH_SERVICES": "app app-extra"}

    result = run_check_health(env=env)

    assert result.returncode == 0, result.stderr
    assert "Warning:" not in result.stderr

    calls = docker_stub.read_calls()
    assert calls == [
        ["compose", "config", "--services"],
        ["compose", "ps"],
        ["compose", "logs", "--tail=50", "app"],
        ["compose", "logs", "--tail=50", "app-extra"],
    ]
