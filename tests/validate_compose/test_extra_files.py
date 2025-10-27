from __future__ import annotations

import os
import subprocess
from pathlib import Path
from typing import TYPE_CHECKING

from tests.helpers.compose_instances import ComposeInstancesData

from .utils import expected_compose_call

if TYPE_CHECKING:
    from ..conftest import DockerStub


def _select_instance(compose_instances_data: ComposeInstancesData) -> str:
    if "core" in compose_instances_data.instance_names:
        return "core"
    return compose_instances_data.instance_names[0]


def _compose_plan_paths(
    repo_copy: Path, compose_instances_data: ComposeInstancesData, instance: str
) -> list[Path]:
    return [repo_copy / Path(entry) for entry in compose_instances_data.compose_plan(instance)]


def _env_chain_paths(
    repo_copy: Path, compose_instances_data: ComposeInstancesData, instance: str
) -> list[Path]:
    return [repo_copy / Path(entry) for entry in compose_instances_data.env_files_map.get(instance, [])]


def test_prefers_local_env_when_available(
    repo_copy: Path,
    docker_stub: DockerStub,
    compose_instances_data: ComposeInstancesData,
) -> None:
    docker_stub.set_exit_code(0)

    instance = _select_instance(compose_instances_data)
    env_chain = _env_chain_paths(repo_copy, compose_instances_data, instance)
    base_files = _compose_plan_paths(repo_copy, compose_instances_data, instance)

    result = subprocess.run(
        [str(repo_copy / "scripts" / "validate_compose.sh")],
        capture_output=True,
        text=True,
        check=False,
        cwd=repo_copy,
        env={**os.environ, "COMPOSE_INSTANCES": instance},
    )

    assert result.returncode == 0, result.stderr
    calls = docker_stub.read_calls()
    assert len(calls) == 1
    (call,) = calls
    assert call == expected_compose_call(
        env_chain,
        base_files,
        "config",
    )


def test_includes_extra_files_from_env_file(
    repo_copy: Path,
    docker_stub: DockerStub,
    compose_instances_data: ComposeInstancesData,
) -> None:
    docker_stub.set_exit_code(0)

    overlay_dir = repo_copy / "compose" / "overlays"
    overlay_dir.mkdir(parents=True, exist_ok=True)
    extra_files = ["metrics.yml", "logging.yml"]
    for name in extra_files:
        (overlay_dir / name).write_text(
            "version: '3.9'\nservices:\n  placeholder:\n    image: busybox:latest\n",
            encoding="utf-8",
        )

    env_file = repo_copy / "env" / "local" / "core.env"
    env_file.write_text(
        env_file.read_text(encoding="utf-8")
        + "COMPOSE_EXTRA_FILES=compose/overlays/metrics.yml compose/overlays/logging.yml\n",
        encoding="utf-8",
    )

    instance = _select_instance(compose_instances_data)
    env_chain = _env_chain_paths(repo_copy, compose_instances_data, instance)
    base_files = _compose_plan_paths(repo_copy, compose_instances_data, instance)

    result = subprocess.run(
        [str(repo_copy / "scripts" / "validate_compose.sh")],
        capture_output=True,
        text=True,
        check=False,
        cwd=repo_copy,
        env={**os.environ, "COMPOSE_INSTANCES": instance},
    )

    assert result.returncode == 0, result.stderr
    calls = docker_stub.read_calls()
    assert len(calls) == 1
    (call,) = calls
    assert call == expected_compose_call(
        env_chain,
        base_files
        + [
            repo_copy / "compose" / "overlays" / "metrics.yml",
            repo_copy / "compose" / "overlays" / "logging.yml",
        ],
        "config",
    )


def test_env_override_for_extra_files(
    repo_copy: Path,
    docker_stub: DockerStub,
    compose_instances_data: ComposeInstancesData,
) -> None:
    docker_stub.set_exit_code(0)

    overlay_dir = repo_copy / "compose" / "overlays"
    overlay_dir.mkdir(parents=True, exist_ok=True)
    (overlay_dir / "custom.yml").write_text(
        "version: '3.9'\nservices:\n  custom:\n    image: busybox:latest\n",
        encoding="utf-8",
    )
    (overlay_dir / "metrics.yml").write_text(
        "version: '3.9'\nservices:\n  metrics:\n    image: busybox:latest\n",
        encoding="utf-8",
    )

    env_file = repo_copy / "env" / "local" / "core.env"
    env_file.write_text(
        env_file.read_text(encoding="utf-8")
        + "COMPOSE_EXTRA_FILES=compose/overlays/metrics.yml\n",
        encoding="utf-8",
    )

    instance = _select_instance(compose_instances_data)
    env_chain = _env_chain_paths(repo_copy, compose_instances_data, instance)
    base_files = _compose_plan_paths(repo_copy, compose_instances_data, instance)

    result = subprocess.run(
        [str(repo_copy / "scripts" / "validate_compose.sh")],
        capture_output=True,
        text=True,
        check=False,
        cwd=repo_copy,
        env={
            **os.environ,
            "COMPOSE_INSTANCES": instance,
            "COMPOSE_EXTRA_FILES": "compose/overlays/custom.yml",
        },
    )

    assert result.returncode == 0, result.stderr
    calls = docker_stub.read_calls()
    assert len(calls) == 1
    (call,) = calls
    assert call == expected_compose_call(
        env_chain,
        base_files
        + [
            repo_copy / "compose" / "overlays" / "custom.yml",
        ],
        "config",
    )
