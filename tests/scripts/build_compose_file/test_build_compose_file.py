from __future__ import annotations

from pathlib import Path

from tests.helpers.compose_instances import ComposeInstancesData
from .utils import create_compose_config_stub, run_build_compose_file

GENERATED_HEADER = (
    "# GENERATED FILE. DO NOT EDIT. RE-RUN SCRIPTS/BUILD_COMPOSE_FILE.SH OR "
    "SCRIPTS/DEPLOY_INSTANCE.SH."
)


def _extract_args(command: list[str], flag: str) -> list[str]:
    values: list[str] = []
    for index, entry in enumerate(command):
        if entry == flag and index + 1 < len(command):
            values.append(command[index + 1])
    return values


def test_requires_instance(repo_copy: Path, tmp_path: Path) -> None:
    stub = create_compose_config_stub(tmp_path)

    result = run_build_compose_file(
        env={"DOCKER_COMPOSE_BIN": str(stub.path), **stub.base_env},
        cwd=repo_copy,
        script_path=repo_copy / "scripts" / "build_compose_file.sh",
    )

    assert result.returncode == 64
    assert "instance argument is required" in result.stderr


def test_generates_compose_from_instance_plan(
    repo_copy: Path, compose_instances_data: ComposeInstancesData, tmp_path: Path
) -> None:
    output_path = repo_copy / "docker-compose.yml"
    stub = create_compose_config_stub(tmp_path, output_content="version: '3.8'\nservices: {}\n")

    result = run_build_compose_file(
        args=["--output", str(output_path), "core"],
        env={"DOCKER_COMPOSE_BIN": str(stub.path), **stub.base_env},
        cwd=repo_copy,
        script_path=repo_copy / "scripts" / "build_compose_file.sh",
    )

    assert result.returncode == 0, result.stderr
    assert output_path.read_text(encoding="utf-8") == (
        f"{GENERATED_HEADER}\n{stub.output_content}"
    )

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
    extra_env1.write_text("PLACEHOLDER=1\n", encoding="utf-8")

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
            "--file",
            str(extra_file_cli.relative_to(repo_copy)),
            "--env-file",
            str(extra_env2.relative_to(repo_copy)),
            "--env-file",
            str(extra_env3.relative_to(repo_copy)),
            "--output",
            str(output_path),
            "core",
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


def test_writes_consolidated_env_output_with_order(
    repo_copy: Path, tmp_path: Path
) -> None:
    stub = create_compose_config_stub(tmp_path)

    base_env_file = repo_copy / "env" / "custom-base.env"
    override_env_file = repo_copy / "env" / "custom-override.env"
    base_env_file.write_text(
        "ALPHA=1\nSHARED=from_base\nOVERRIDE=keep\n",
        encoding="utf-8",
    )
    override_env_file.write_text(
        "SHARED=from_override\nNEW_VAR=value\n", encoding="utf-8"
    )

    env_output = repo_copy / "artifacts" / "env" / "merged.env"
    env_output.parent.mkdir(parents=True, exist_ok=True)
    env_output.write_text("SHOULD_BE_REPLACED=1\n", encoding="utf-8")

    result = run_build_compose_file(
        args=[
            "--env-file",
            str(override_env_file.relative_to(repo_copy)),
            "--env-output",
            str(env_output.relative_to(repo_copy)),
            "core",
        ],
        env={
            "DOCKER_COMPOSE_BIN": str(stub.path),
            **stub.base_env,
            "COMPOSE_ENV_FILES": str(base_env_file.relative_to(repo_copy)),
        },
        cwd=repo_copy,
        script_path=repo_copy / "scripts" / "build_compose_file.sh",
    )

    assert result.returncode == 0, result.stderr
    assert env_output.read_text(encoding="utf-8") == (
        f"{GENERATED_HEADER}\n"
        "ALPHA=1\nSHARED=from_override\nOVERRIDE=keep\nNEW_VAR=value\n"
        f"REPO_ROOT={repo_copy}\n"
        "LOCAL_INSTANCE=core\n"
    )
    assert str(env_output) in result.stdout

    calls = stub.read_calls()
    env_files = _extract_args(calls[0], "--env-file")
    assert env_files == [str(base_env_file.resolve()), str(override_env_file.resolve())]


def test_refreshes_default_env_output(repo_copy: Path, tmp_path: Path) -> None:
    stub = create_compose_config_stub(tmp_path)

    default_env_output = repo_copy / ".env"
    default_env_output.write_text("OLD=1\n", encoding="utf-8")

    core_env = repo_copy / "env" / "local" / "core.env"
    core_env.write_text(
        "APP_SECRET=override-secret\nAPP_DATA_UID=2000\n",
        encoding="utf-8",
    )

    result = run_build_compose_file(
        args=["core"],
        env={"DOCKER_COMPOSE_BIN": str(stub.path), **stub.base_env},
        cwd=repo_copy,
        script_path=repo_copy / "scripts" / "build_compose_file.sh",
    )

    assert result.returncode == 0, result.stderr

    output_lines = default_env_output.read_text(encoding="utf-8").splitlines()
    assert output_lines == [
        GENERATED_HEADER,
        "TZ=UTC",
        "APP_SECRET=override-secret",
        "APP_RETENTION_HOURS=24",
        "APP_DATA_UID=2000",
        "APP_DATA_GID=1000",
        f"REPO_ROOT={repo_copy}",
        "LOCAL_INSTANCE=core",
    ]
