from __future__ import annotations

from pathlib import Path

from tests.conftest import DockerStub
from tests.helpers.compose_instances import ComposeInstancesData

from .utils import (
    _expected_compose_call,
    expected_consolidated_plan_calls,
    run_check_health,
)


def _derive_service_names(
    compose_instances_data: ComposeInstancesData, instance: str
) -> list[str]:
    services = set(compose_instances_data.instance_app_names.get(instance, []))
    for entry in compose_instances_data.compose_plan(instance):
        if entry.startswith("compose/apps/"):
            parts = entry.split("/")
            if len(parts) >= 3:
                services.add(parts[2])
    if not services:
        services.add("app")
    return sorted(services)


def test_infers_compose_files_and_env_from_instance(
    docker_stub: DockerStub,
    repo_copy: Path,
    compose_instances_data: ComposeInstancesData,
) -> None:
    script_path = repo_copy / "scripts" / "check_health.sh"

    service_names = _derive_service_names(compose_instances_data, "core")
    services_output = "\n".join(service_names)

    result = run_check_health(
        args=["core"],
        cwd=repo_copy,
        script_path=script_path,
        env={
            "DOCKER_STUB_SERVICES_OUTPUT": services_output,
            "HEALTH_SERVICES": services_output,
        },
    )

    assert result.returncode == 0, result.stderr

    calls = docker_stub.read_calls()
    expected_env_files = [
        str((repo_copy / relative).resolve(strict=False))
        for relative in compose_instances_data.env_files_map.get("core", [])
        if relative
    ]
    expected_files = [
        str((repo_copy / relative).resolve(strict=False))
        for relative in compose_instances_data.compose_plan("core")
    ]
    consolidated_file = repo_copy / "docker-compose.yml"

    expected_prefix = expected_consolidated_plan_calls(
        expected_env_files, expected_files, consolidated_file
    )
    expected_prefix.extend(
        [
            _expected_compose_call(None, [consolidated_file], "config", "--services"),
            _expected_compose_call(None, [consolidated_file], "ps"),
        ]
    )

    assert calls[:4] == expected_prefix

    log_calls = [call for call in calls[4:] if "logs" in call]
    logged_services = [call[-1] for call in log_calls if call]
    expected_primary = ["core"]
    allowed_services = set(service_names) | set(expected_primary)
    assert set(logged_services).issubset(allowed_services)
    assert len(logged_services) == len(set(logged_services))
    assert logged_services
    for call in log_calls:
        service = call[-1]
        assert call == _expected_compose_call(
            None, [consolidated_file], "logs", "--tail=50", service
        )


def test_executes_from_scripts_directory(
    docker_stub: DockerStub,
    repo_copy: Path,
    compose_instances_data: ComposeInstancesData,
) -> None:
    scripts_dir = repo_copy / "scripts"

    service_names = _derive_service_names(compose_instances_data, "core")
    services_output = "\n".join(service_names)

    result = run_check_health(
        args=["core"],
        cwd=scripts_dir,
        script_path="./check_health.sh",
        env={
            "DOCKER_STUB_SERVICES_OUTPUT": services_output,
            "HEALTH_SERVICES": services_output,
        },
    )

    assert result.returncode == 0, result.stderr

    calls = docker_stub.read_calls()
    expected_env_files = [
        str((repo_copy / relative).resolve(strict=False))
        for relative in compose_instances_data.env_files_map.get("core", [])
        if relative
    ]
    expected_files = [
        str((repo_copy / relative).resolve(strict=False))
        for relative in compose_instances_data.compose_plan("core")
    ]
    consolidated_file = repo_copy / "docker-compose.yml"

    expected_prefix = expected_consolidated_plan_calls(
        expected_env_files, expected_files, consolidated_file
    )
    expected_prefix.extend(
        [
            _expected_compose_call(None, [consolidated_file], "config", "--services"),
            _expected_compose_call(None, [consolidated_file], "ps"),
        ]
    )

    assert calls[:4] == expected_prefix

    log_calls = [call for call in calls[4:] if "logs" in call]
    logged_services = [call[-1] for call in log_calls if call]
    expected_primary = ["core"]
    allowed_services = set(service_names) | set(expected_primary)
    assert set(logged_services).issubset(allowed_services)
    assert len(logged_services) == len(set(logged_services))
    assert logged_services
    for call in log_calls:
        service = call[-1]
        assert call == _expected_compose_call(
            None, [consolidated_file], "logs", "--tail=50", service
        )
