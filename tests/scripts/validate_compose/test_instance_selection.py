from __future__ import annotations

from pathlib import Path
from typing import TYPE_CHECKING

import textwrap

import pytest

from .utils import (
    REPO_ROOT,
    expected_consolidated_calls,
    get_instance_metadata_map,
    load_instance_metadata,
    run_validate_compose,
)

if TYPE_CHECKING:
    from ..conftest import DockerStub


def _parse_instances(value: str) -> list[str]:
    tokens: list[str] = []
    for chunk in value.split(","):
        chunk = chunk.strip()
        if not chunk:
            continue
        for token in chunk.split():
            token = token.strip()
            if token:
                tokens.append(token)
    return tokens


def test_accepts_mixed_separators_and_invokes_compose_for_each_instance(
    docker_stub: DockerStub,
) -> None:
    docker_stub.set_exit_code(0)

    metadata_sequence = list(load_instance_metadata())
    assert metadata_sequence, "Expected at least one compose instance for validation tests"

    names = [metadata.name for metadata in metadata_sequence]
    if len(names) >= 2:
        instances = f" {names[0]} , , {names[1]}  ,  {names[0]} "
    else:
        instances = f" {names[0]} , , {names[0]}  ,  {names[0]} "

    result = run_validate_compose({"COMPOSE_INSTANCES": instances})

    assert result.returncode == 0, result.stderr
    calls = docker_stub.read_calls()
    parsed_instances = _parse_instances(instances)

    seen: set[str] = set()
    unique_instances: list[str] = []
    for name in parsed_instances:
        if name not in seen:
            seen.add(name)
            unique_instances.append(name)

    assert len(calls) == len(unique_instances) * 2

    metadata_map = get_instance_metadata_map()

    for offset, instance_name in enumerate(unique_instances):
        assert instance_name in metadata_map, f"Unknown instance '{instance_name}' in test setup"
        metadata = metadata_map[instance_name]
        expected_env = metadata.resolved_env_chain()
        expected_files = metadata.compose_files()
        start = offset * 2
        assert calls[start : start + 2] == expected_consolidated_calls(
            expected_env, expected_files, REPO_ROOT / "docker-compose.yml"
        )


def test_unknown_instance_returns_error(docker_stub: DockerStub) -> None:
    result = run_validate_compose({"COMPOSE_INSTANCES": "unknown"})

    assert result.returncode == 1
    assert "unknown instance" in result.stderr
    assert docker_stub.read_calls() == []


def test_errors_when_compose_command_missing(docker_stub: DockerStub) -> None:
    metadata_sequence = list(load_instance_metadata())
    assert metadata_sequence, "Expected at least one compose instance for validation tests"
    target_instance = metadata_sequence[0].name

    env = {
        "DOCKER_COMPOSE_BIN": "definitely-missing-binary",
        "COMPOSE_INSTANCES": target_instance,
    }

    result = run_validate_compose(env)

    assert result.returncode == 127
    assert (
        "Error: definitely-missing-binary is not available. Set DOCKER_COMPOSE_BIN if needed."
        in result.stderr
    )
    assert docker_stub.read_calls() == []


@pytest.mark.parametrize("instances", [" , ,  "])
def test_only_separators_in_compose_instances_returns_error(
    instances: str, docker_stub: DockerStub
) -> None:
    result = run_validate_compose({"COMPOSE_INSTANCES": instances})

    assert result.returncode == 1
    assert "Error: no instance provided for validation." in result.stderr
    assert docker_stub.read_calls() == []


def test_reports_failure_when_compose_command_fails_with_docker_stub(
    docker_stub: DockerStub,
) -> None:
    docker_stub.set_exit_code(1)

    metadata_sequence = list(load_instance_metadata())
    assert metadata_sequence, "Expected at least one compose instance for validation tests"
    target_instance = metadata_sequence[0].name

    result = run_validate_compose({"COMPOSE_INSTANCES": target_instance})

    assert result.returncode != 0
    assert (
        f"[x] instance=\"{target_instance}\" (docker compose config -q exited with status 1)"
        in result.stderr
    )

    metadata_map = get_instance_metadata_map()
    files = metadata_map[target_instance].compose_files()
    for file in files:
        assert str(file) in result.stderr

    calls = docker_stub.read_calls()
    assert len(calls) == 2


def test_compose_failure_reports_diagnostics(tmp_path: Path) -> None:
    metadata_sequence = list(load_instance_metadata())
    assert metadata_sequence, "Expected at least one compose instance for validation tests"

    target_instance = metadata_sequence[0].name

    compose_script = tmp_path / "fake-compose"
    compose_script.write_text(
        textwrap.dedent(
            """#!/usr/bin/env bash
            echo "line-from-compose stdout"
            echo "line-from-compose stderr" >&2
            exit 23
            """
        ).strip()
        + "\n",
        encoding="utf-8",
    )
    compose_script.chmod(0o755)

    result = run_validate_compose(
        {
            "COMPOSE_INSTANCES": target_instance,
            "DOCKER_COMPOSE_BIN": str(compose_script),
        }
    )

    assert result.returncode != 0

    stderr_lines = result.stderr.splitlines()
    assert any(
        line
        == f"[x] instance=\"{target_instance}\" (docker compose config -q exited with status 23)"
        for line in stderr_lines
    ), result.stderr

    metadata_map = get_instance_metadata_map()
    metadata = metadata_map[target_instance]

    expected_files = " ".join(str(path) for path in metadata.compose_files())
    files_line = next(
        (line.strip() for line in stderr_lines if line.strip().startswith("files:")),
        "",
    )
    assert files_line == f"files: {expected_files}"

    env_line = next(
        (line.strip() for line in stderr_lines if line.strip().startswith("env files:")),
        "",
    )
    resolved_env_chain = [str(path) for path in metadata.resolved_env_chain()]
    if resolved_env_chain:
        assert env_line == f"env files: {' '.join(resolved_env_chain)}"
    else:
        assert env_line == "env files: (none)"

    derived_line = next(
        (line.strip() for line in stderr_lines if line.strip().startswith("derived env:")),
        "",
    )
    assert derived_line.startswith("derived env: APP_DATA_DIR=")
    assert "APP_DATA_DIR_MOUNT=" in derived_line

    assert "docker compose config output:" in result.stderr
    assert "     line-from-compose stdout" in result.stderr
    assert "     line-from-compose stderr" in result.stderr
