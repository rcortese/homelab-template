from __future__ import annotations

from pathlib import Path

from tests.conftest import DockerStub

from .utils import (
    _expected_compose_call,
    expected_consolidated_plan_calls,
    run_check_health,
)


def test_invokes_ps_and_logs_with_custom_files(docker_stub: DockerStub) -> None:
    env = {
        "COMPOSE_FILES": "compose/base.yml compose/extra.yml",
        "COMPOSE_ENV_FILE": "env/common.example.env",
    }

    result = run_check_health(env=env)

    assert result.returncode == 0, result.stderr

    calls = docker_stub.read_calls()
    repo_root = Path(__file__).resolve().parents[3]
    expected_env = str((repo_root / "env" / "common.example.env").resolve())
    consolidated_file = repo_root / "docker-compose.yml"

    compose_files = [
        (repo_root / "compose" / "base.yml").resolve(),
        (repo_root / "compose" / "extra.yml").resolve(),
    ]
    assert calls == expected_consolidated_plan_calls(
        expected_env, compose_files, consolidated_file
    ) + [
        _expected_compose_call(None, [consolidated_file], "config", "--services"),
        _expected_compose_call(None, [consolidated_file], "ps"),
        _expected_compose_call(
            None,
            [consolidated_file],
            "logs",
            "--tail=50",
            "app",
        ),
    ]


def test_loads_compose_extra_files_from_env_file(
    docker_stub: DockerStub, tmp_path: Path
) -> None:
    env_file = tmp_path / "custom.env"
    env_file.write_text(
        "COMPOSE_EXTRA_FILES=compose/overlays/extra.yml\n",
        encoding="utf-8",
    )

    env = {
        "COMPOSE_FILES": "compose/base.yml",
        "COMPOSE_ENV_FILE": str(env_file),
    }

    result = run_check_health(env=env)

    assert result.returncode == 0, result.stderr
    assert "Warning:" not in result.stderr
    assert "[*] Containers:" in result.stdout

    repo_root = Path(__file__).resolve().parents[3]
    consolidated_file = repo_root / "docker-compose.yml"
    expected_files = [
        (repo_root / "compose" / "base.yml").resolve(),
        (repo_root / "compose" / "overlays" / "extra.yml").resolve(),
        (repo_root / "compose" / "overlays" / "extra.yml").resolve(),
    ]
    calls = docker_stub.read_calls()
    assert calls == expected_consolidated_plan_calls(
        str(env_file), expected_files, consolidated_file
    ) + [
        _expected_compose_call(None, [consolidated_file], "config", "--services"),
        _expected_compose_call(None, [consolidated_file], "ps"),
        _expected_compose_call(
            None, [consolidated_file], "logs", "--tail=50", "app"
        ),
    ]


def test_ignores_blank_and_duplicate_compose_tokens(docker_stub: DockerStub) -> None:
    repo_root = Path(__file__).resolve().parents[3]
    compose_base = "compose/base.yml"

    env = {
        "COMPOSE_FILES": f"  {compose_base}   \n   {compose_base}    ",
        "COMPOSE_EXTRA_FILES": f"  {compose_base}    {compose_base}\n   {compose_base}   ",
    }

    result = run_check_health(env=env)

    assert result.returncode == 0, result.stderr
    assert "Warning:" not in result.stderr
    assert "[*] Containers:" in result.stdout

    expected_manifest = str((repo_root / compose_base).resolve())
    consolidated_file = repo_root / "docker-compose.yml"
    calls = docker_stub.read_calls()
    assert calls, "Expected docker compose invocations to be recorded"

    plan_calls = expected_consolidated_plan_calls(
        None, [expected_manifest, expected_manifest], consolidated_file
    )
    assert calls[:2] == plan_calls

    for call in calls[2:]:
        assert "-f" in call, call
        manifest_args = [
            call[idx + 1]
            for idx, token in enumerate(call)
            if token == "-f" and idx + 1 < len(call)
        ]
        assert manifest_args, "No compose manifests were passed to docker compose"
        assert manifest_args == [str(consolidated_file)]
