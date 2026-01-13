from __future__ import annotations

from pathlib import Path
from typing import TYPE_CHECKING

from .utils import load_instance_metadata, run_validate_compose

if TYPE_CHECKING:
    from ..conftest import DockerStub


def test_legacy_compose_failure_prints_root_cause_and_plan_order(
    docker_stub: DockerStub,
    repo_copy: Path,
) -> None:
    docker_stub.set_exit_code(1)

    metadata_sequence = list(load_instance_metadata(repo_copy))
    assert metadata_sequence, "Expected at least one compose instance for validation tests"
    metadata = metadata_sequence[0]

    result = run_validate_compose(
        {
            "COMPOSE_INSTANCES": metadata.name,
            "VALIDATE_USE_LEGACY_PLAN": "true",
            "DOCKER_STUB_CONFIG_STDERR": "yaml parse error on line 12",
        },
        cwd=repo_copy,
    )

    assert result.returncode != 0
    assert (
        f"[x] instance=\"{metadata.name}\" (docker compose config exited with status 1)"
        in result.stderr
    )
    assert "Root cause (from docker compose): yaml parse error on line 12" in result.stderr
    assert "compose plan order:" in result.stderr

    expected_files = metadata.compose_files(repo_copy)
    expected_files_blob = " ".join(str(path) for path in expected_files)
    assert f"failing files: {expected_files_blob}" in result.stderr

    for index, file_path in enumerate(expected_files, start=1):
        assert f"{index}. {file_path}" in result.stderr
