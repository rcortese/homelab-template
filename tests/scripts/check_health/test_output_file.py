from __future__ import annotations

from pathlib import Path

from tests.conftest import DockerStub

from .utils import run_check_health


def test_json_output_writes_file_with_matching_content(
    docker_stub: DockerStub, tmp_path: Path
) -> None:
    output_file = tmp_path / "status.json"

    env = {"DOCKER_STUB_SERVICES_OUTPUT": "svc-core"}

    result = run_check_health(
        args=["--format", "json", "--output", str(output_file)],
        env=env,
    )

    assert result.returncode == 0, result.stderr
    assert output_file.exists()

    file_content = output_file.read_text(encoding="utf-8")
    assert file_content == result.stdout


def test_output_file_not_created_when_execution_fails(tmp_path: Path) -> None:
    output_file = tmp_path / "status.json"

    env = {"DOCKER_COMPOSE_BIN": "definitely-missing-binary"}

    result = run_check_health(
        args=["--format", "json", "--output", str(output_file)],
        env=env,
    )

    assert result.returncode != 0
    assert not output_file.exists()
