from __future__ import annotations

from typing import TYPE_CHECKING

import pytest

from .utils import (
    APP_BASE_COMPOSE,
    BASE_COMPOSE,
    CORE_COMPOSE,
    CORE_ENV,
    CORE_ENV_LOCAL,
    MEDIA_COMPOSE,
    MEDIA_ENV,
    MEDIA_ENV_LOCAL,
    MONITORING_BASE_COMPOSE,
    MONITORING_CORE_COMPOSE,
    expected_compose_call,
    run_validate_compose,
)

if TYPE_CHECKING:
    from ..conftest import DockerStub


@pytest.mark.parametrize("instances", [" core , , media  ,  core "])
def test_accepts_mixed_separators_and_invokes_compose_for_each_instance(
    instances: str, docker_stub: DockerStub
) -> None:
    docker_stub.set_exit_code(0)

    result = run_validate_compose({"COMPOSE_INSTANCES": instances})

    assert result.returncode == 0, result.stderr
    calls = docker_stub.read_calls()
    assert len(calls) == 2

    core_call, media_call = calls
    expected_core_env = CORE_ENV_LOCAL if CORE_ENV_LOCAL.exists() else CORE_ENV
    expected_media_env = MEDIA_ENV_LOCAL if MEDIA_ENV_LOCAL.exists() else MEDIA_ENV
    assert core_call == expected_compose_call(
        expected_core_env,
        [
            BASE_COMPOSE,
            APP_BASE_COMPOSE,
            CORE_COMPOSE,
            MONITORING_BASE_COMPOSE,
            MONITORING_CORE_COMPOSE,
        ],
        "config",
    )
    assert media_call == expected_compose_call(
        expected_media_env,
        [BASE_COMPOSE, APP_BASE_COMPOSE, MEDIA_COMPOSE],
        "config",
    )


def test_unknown_instance_returns_error(docker_stub: DockerStub) -> None:
    result = run_validate_compose({"COMPOSE_INSTANCES": "unknown"})

    assert result.returncode == 1
    assert "instância desconhecida" in result.stderr
    assert docker_stub.read_calls() == []


@pytest.mark.parametrize("instances", [" , ,  "])
def test_only_separators_in_compose_instances_returns_error(
    instances: str, docker_stub: DockerStub
) -> None:
    result = run_validate_compose({"COMPOSE_INSTANCES": instances})

    assert result.returncode == 1
    assert "Error: nenhuma instância informada para validação." in result.stderr
    assert docker_stub.read_calls() == []


def test_reports_failure_when_compose_command_fails_with_docker_stub(
    docker_stub: DockerStub,
) -> None:
    docker_stub.set_exit_code(1)

    result = run_validate_compose({"COMPOSE_INSTANCES": "core"})

    assert result.returncode != 0
    assert "✖ instância=\"core\"" in result.stderr
    assert str(BASE_COMPOSE) in result.stderr
    assert str(CORE_COMPOSE) in result.stderr

    calls = docker_stub.read_calls()
    assert len(calls) == 1
