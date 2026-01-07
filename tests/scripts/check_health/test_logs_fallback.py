from __future__ import annotations

import pytest
from pathlib import Path

from tests.conftest import DockerStub

from .utils import run_check_health


def _strip_env_and_file_flags(call: list[str]) -> list[str]:
    cleaned: list[str] = []
    skip_next = False
    for token in call:
        if skip_next:
            skip_next = False
            continue
        if token in {"--env-file", "-f", "--output"}:
            if token == "--output":
                cleaned.append(token)
            skip_next = True
            continue
        cleaned.append(token)
    return cleaned


def test_logs_fallback_through_alternative_services(
    docker_stub: DockerStub, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    state_file = tmp_path / "fail_once_state"
    docker_stub.reset_fail_once_state()
    if state_file.exists():
        state_file.unlink()
    monkeypatch.setenv("HEALTH_SERVICES", "svc-core")
    monkeypatch.setenv("DOCKER_STUB_FAIL_ONCE_FOR", "svc-core")
    monkeypatch.setenv("DOCKER_STUB_FAIL_ONCE_STATE", str(state_file))
    monkeypatch.setenv("DOCKER_STUB_SERVICES_OUTPUT", "svc-api")

    result = run_check_health(args=["core"])

    assert result.returncode == 0, result.stderr

    calls = [
        _strip_env_and_file_flags(entry) for entry in docker_stub.read_calls()
    ]
    assert calls == [
        ["compose", "config", "--output"],
        ["compose", "config", "-q"],
        ["compose", "config", "--services"],
        ["compose", "ps"],
        ["compose", "logs", "--tail=50", "svc-core"],
        ["compose", "logs", "--tail=50", "svc-api"],
    ]


def test_logs_reports_failure_when_all_services_fail(
    docker_stub: DockerStub, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("DOCKER_STUB_ALWAYS_FAIL_LOGS", "1")

    env = {
        "HEALTH_SERVICES": "svc-main svc-core svc-media",
        "DOCKER_STUB_SERVICES_OUTPUT": "svc-aux",
    }

    result = run_check_health(args=["core"], env=env)

    assert result.returncode != 0
    assert "Failed to retrieve logs for services" in result.stderr

    calls = [
        _strip_env_and_file_flags(entry) for entry in docker_stub.read_calls()
    ]
    assert calls == [
        ["compose", "config", "--output"],
        ["compose", "config", "-q"],
        ["compose", "config", "--services"],
        ["compose", "ps"],
        ["compose", "logs", "--tail=50", "svc-main"],
        ["compose", "logs", "--tail=50", "svc-core"],
        ["compose", "logs", "--tail=50", "svc-media"],
        ["compose", "logs", "--tail=50", "svc-aux"],
    ]


def test_logs_handles_comma_separated_health_services(docker_stub: DockerStub) -> None:
    env = {
        "HEALTH_SERVICES": "svc-core,svc-extra",
        "DOCKER_STUB_FAIL_ALWAYS_FOR": "svc-core",
        "DOCKER_STUB_SERVICES_OUTPUT": "svc-auto",
    }

    result = run_check_health(args=["core"], env=env)

    assert result.returncode == 0, result.stderr
    assert "Warning: Failed to retrieve logs for services: svc-core" in result.stderr

    calls = [
        _strip_env_and_file_flags(entry) for entry in docker_stub.read_calls()
    ]
    assert calls == [
        ["compose", "config", "--output"],
        ["compose", "config", "-q"],
        ["compose", "config", "--services"],
        ["compose", "ps"],
        ["compose", "logs", "--tail=50", "svc-core"],
        ["compose", "logs", "--tail=50", "svc-extra"],
        ["compose", "logs", "--tail=50", "svc-auto"],
    ]


def test_logs_attempts_all_services_even_after_success(docker_stub: DockerStub) -> None:
    env = {
        "HEALTH_SERVICES": "svc-main svc-extra",
        "DOCKER_STUB_SERVICES_OUTPUT": "svc-auto",
    }

    result = run_check_health(args=["core"], env=env)

    assert result.returncode == 0, result.stderr
    assert "Warning:" not in result.stderr

    calls = [
        _strip_env_and_file_flags(entry) for entry in docker_stub.read_calls()
    ]
    assert calls == [
        ["compose", "config", "--output"],
        ["compose", "config", "-q"],
        ["compose", "config", "--services"],
        ["compose", "ps"],
        ["compose", "logs", "--tail=50", "svc-main"],
        ["compose", "logs", "--tail=50", "svc-extra"],
        ["compose", "logs", "--tail=50", "svc-auto"],
    ]


def test_logs_without_targets_uses_compose_services(docker_stub: DockerStub) -> None:
    env = {"DOCKER_STUB_SERVICES_OUTPUT": "svc-one\nsvc-two"}

    result = run_check_health(args=["core"], env=env)

    assert result.returncode == 0, result.stderr

    calls = [
        _strip_env_and_file_flags(entry) for entry in docker_stub.read_calls()
    ]
    assert calls == [
        ["compose", "config", "--output"],
        ["compose", "config", "-q"],
        ["compose", "config", "--services"],
        ["compose", "ps"],
        ["compose", "logs", "--tail=50", "svc-one"],
        ["compose", "logs", "--tail=50", "svc-two"],
    ]


def test_logs_without_targets_and_no_services_reports_error(
    docker_stub: DockerStub,
) -> None:
    env = {"DOCKER_STUB_SERVICES_OUTPUT": ""}

    result = run_check_health(args=["core"], env=env)

    assert result.returncode != 0
    assert "no services were found" in result.stderr

    calls = [
        _strip_env_and_file_flags(entry) for entry in docker_stub.read_calls()
    ]
    assert calls == [
        ["compose", "config", "--output"],
        ["compose", "config", "-q"],
        ["compose", "config", "--services"],
    ]
