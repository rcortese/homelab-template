from __future__ import annotations

from pathlib import Path

from tests.helpers.compose_instances import ComposeInstancesData
from .utils import create_compose_config_stub, run_build_compose_file


def _extract_args(command: list[str], flag: str) -> list[str]:
    values: list[str] = []
    for index, entry in enumerate(command):
        if entry == flag and index + 1 < len(command):
            values.append(command[index + 1])
    return values


def test_requires_instance_or_compose_files(repo_copy: Path, tmp_path: Path) -> None:
    stub = create_compose_config_stub(tmp_path)

    result = run_build_compose_file(
        env={"DOCKER_COMPOSE_BIN": str(stub.path), **stub.base_env},
        cwd=repo_copy,
        script_path=repo_copy / "scripts" / "build_compose_file.sh",
    )

    assert result.returncode == 64
    assert "nenhuma instância informada" in result.stderr


def test_generates_compose_from_instance_plan(
    repo_copy: Path, compose_instances_data: ComposeInstancesData, tmp_path: Path
) -> None:
    output_path = repo_copy / "docker-compose.yml"
    stub = create_compose_config_stub(tmp_path, output_content="version: '3.8'\nservices: {}\n")

    result = run_build_compose_file(
        args=["--instance", "core", "--output", str(output_path)],
        env={"DOCKER_COMPOSE_BIN": str(stub.path), **stub.base_env},
        cwd=repo_copy,
        script_path=repo_copy / "scripts" / "build_compose_file.sh",
    )

    assert result.returncode == 0, result.stderr
    assert output_path.read_text(encoding="utf-8") == stub.output_content

    calls = stub.read_calls()
    assert len(calls) == 2

    first_call = calls[0]
    env_files = _extract_args(first_call, "--env-file")
    expected_envs = {
        str((repo_copy / "env" / "local" / "common.env").resolve()),
        str((repo_copy / "env" / "local" / "core.env").resolve()),
    }
    assert set(env_files) == expected_envs

    compose_files = _extract_args(first_call, "-f")
    expected_plan = [
        str((repo_copy / entry).resolve())
        for entry in compose_instances_data.compose_plan("core")
    ]
    assert compose_files == expected_plan

    second_call = calls[1]
    assert str(output_path.resolve()) in _extract_args(second_call, "-f")


def test_applies_extras_and_explicit_env_chain(
    repo_copy: Path, compose_instances_data: ComposeInstancesData, tmp_path: Path
) -> None:
    stub = create_compose_config_stub(tmp_path)

    extra_env1 = repo_copy / "env" / "custom1.env"
    extra_env2 = repo_copy / "env" / "custom2.env"
    extra_env3 = repo_copy / "env" / "custom3.env"
    for env_file in (extra_env1, extra_env2, extra_env3):
        env_file.write_text("PLACEHOLDER=1\n", encoding="utf-8")

    extras_dir = repo_copy / "compose" / "extras"
    extras_dir.mkdir(parents=True, exist_ok=True)

    extra_file_env = extras_dir / "extra-env.yml"
    extra_file_cli = extras_dir / "extra-cli.yml"
    extra_file_env.write_text("version: '3.8'\n", encoding="utf-8")
    extra_file_cli.write_text("version: '3.8'\n", encoding="utf-8")

    env_overrides = {
        "COMPOSE_EXTRA_FILES": str(extra_file_env.relative_to(repo_copy)),
        "COMPOSE_ENV_FILES": f"{extra_env1.relative_to(repo_copy)} {extra_env2.relative_to(repo_copy)}",
    }

    output_path = repo_copy / "generated.yml"
    result = run_build_compose_file(
        args=[
            "--instance",
            "core",
            "--file",
            str(extra_file_cli.relative_to(repo_copy)),
            "--env-file",
            str(extra_env2.relative_to(repo_copy)),
            "--env-file",
            str(extra_env3.relative_to(repo_copy)),
            "--output",
            str(output_path),
        ],
        env={"DOCKER_COMPOSE_BIN": str(stub.path), **stub.base_env, **env_overrides},
        cwd=repo_copy,
        script_path=repo_copy / "scripts" / "build_compose_file.sh",
    )

    assert result.returncode == 0, result.stderr
    assert output_path.exists()

    calls = stub.read_calls()
    assert len(calls) == 2

    first_call = calls[0]
    env_files = _extract_args(first_call, "--env-file")
    expected_env_chain = [
        str(extra_env1.resolve()),
        str(extra_env2.resolve()),
        str(extra_env3.resolve()),
    ]
    assert env_files == expected_env_chain

    compose_files = _extract_args(first_call, "-f")
    expected_plan = [
        str((repo_copy / entry).resolve())
        for entry in compose_instances_data.compose_plan(
            "core",
            [
                str(extra_file_env.relative_to(repo_copy)),
                str(extra_file_cli.relative_to(repo_copy)),
            ],
        )
    ]
    assert compose_files == expected_plan

    second_call = calls[1]
    assert str(output_path.resolve()) in _extract_args(second_call, "-f")
