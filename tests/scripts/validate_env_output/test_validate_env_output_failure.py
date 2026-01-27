from __future__ import annotations

import subprocess
from pathlib import Path

from tests.helpers.compose_instances import ComposeInstancesData

def run_validate_env_output(repo_root: Path, instance_name: str) -> subprocess.CompletedProcess[str]:
    script_path = repo_root / "scripts" / "validate_env_output.sh"
    return subprocess.run(
        ["bash", str(script_path), instance_name],
        capture_output=True,
        text=True,
        check=False,
        cwd=repo_root,
    )


def _select_instance(compose_instances_data: ComposeInstancesData) -> str:
    if "core" in compose_instances_data.instance_names:
        return "core"
    return compose_instances_data.instance_names[0]


def test_validate_env_output_errors_without_root_env_file(
    repo_copy: Path,
    compose_instances_data: ComposeInstancesData,
) -> None:
    env_path = repo_copy / ".env"
    if env_path.exists():
        env_path.unlink()

    instance_name = _select_instance(compose_instances_data)
    result = run_validate_env_output(repo_copy, instance_name)

    assert result.returncode == 1
    assert "root .env file not found" in result.stderr
    assert "scripts/build_compose_file.sh" in result.stderr


def test_validate_env_output_errors_when_env_out_of_sync(
    repo_copy: Path,
    compose_instances_data: ComposeInstancesData,
) -> None:
    env_path = repo_copy / ".env"
    env_path.write_text("MISMATCHED_ENV=1\n", encoding="utf-8")

    instance_name = _select_instance(compose_instances_data)
    result = run_validate_env_output(repo_copy, instance_name)

    assert result.returncode == 1
    assert "out of sync" in result.stderr
