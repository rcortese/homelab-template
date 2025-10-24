from __future__ import annotations

import os
import shutil
import subprocess
import textwrap
from pathlib import Path

from typing import TYPE_CHECKING

import pytest


if TYPE_CHECKING:
    from .conftest import DockerStub


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = REPO_ROOT / "scripts" / "validate_compose.sh"
BASE_COMPOSE = REPO_ROOT / "compose" / "base.yml"
CORE_COMPOSE = REPO_ROOT / "compose" / "core.yml"
MEDIA_COMPOSE = REPO_ROOT / "compose" / "media.yml"
CORE_ENV = REPO_ROOT / "env" / "core.example.env"
MEDIA_ENV = REPO_ROOT / "env" / "media.example.env"
CORE_ENV_LOCAL = REPO_ROOT / "env" / "local" / "core.env"
MEDIA_ENV_LOCAL = REPO_ROOT / "env" / "local" / "media.env"


def run_validate_compose(env: dict[str, str], cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(SCRIPT_PATH)],
        capture_output=True,
        text=True,
        check=False,
        cwd=cwd or REPO_ROOT,
        env={**os.environ, **env},
    )


@pytest.mark.parametrize("flag", ["-h", "--help"])
def test_help_option_displays_usage_and_exits_successfully(flag: str) -> None:
    result = subprocess.run(
        [str(SCRIPT_PATH), flag],
        capture_output=True,
        text=True,
        check=False,
        cwd=REPO_ROOT,
    )

    expected_help = textwrap.dedent(
        """\
        Uso: scripts/validate_compose.sh

        Valida as instâncias definidas para o repositório garantindo que `docker compose config`
        execute com sucesso para cada combinação de arquivos base + instância.

        Argumentos posicionais:
          (nenhum)

        Variáveis de ambiente relevantes:
          DOCKER_COMPOSE_BIN  Sobrescreve o comando docker compose (ex.: docker-compose).
          COMPOSE_INSTANCES   Lista de instâncias a validar (separadas por espaço ou vírgula). Default: todas.

        Exemplos:
          scripts/validate_compose.sh
          COMPOSE_INSTANCES="media" scripts/validate_compose.sh
        """
    )

    assert result.returncode == 0
    assert result.stdout == expected_help
    assert result.stderr == ""


def test_accepts_mixed_separators_and_invokes_compose_for_each_instance(docker_stub: DockerStub) -> None:
    docker_stub.set_exit_code(0)
    env = {"COMPOSE_INSTANCES": " core , , media  ,  core "}

    result = run_validate_compose(env)

    assert result.returncode == 0, result.stderr
    calls = docker_stub.read_calls()
    assert len(calls) == 2

    core_call, media_call = calls
    expected_core_env = CORE_ENV_LOCAL if CORE_ENV_LOCAL.exists() else CORE_ENV
    expected_media_env = MEDIA_ENV_LOCAL if MEDIA_ENV_LOCAL.exists() else MEDIA_ENV
    assert core_call == [
        "compose",
        "--env-file",
        str(expected_core_env),
        "-f",
        str(BASE_COMPOSE),
        "-f",
        str(CORE_COMPOSE),
        "config",
    ]
    assert media_call == [
        "compose",
        "--env-file",
        str(expected_media_env),
        "-f",
        str(BASE_COMPOSE),
        "-f",
        str(MEDIA_COMPOSE),
        "config",
    ]


def test_unknown_instance_returns_error(docker_stub: DockerStub) -> None:
    result = run_validate_compose({"COMPOSE_INSTANCES": "unknown"})

    assert result.returncode == 1
    assert "instância desconhecida" in result.stderr
    assert docker_stub.read_calls() == []


def test_reports_failure_when_compose_command_fails_with_docker_stub(
    docker_stub: DockerStub,
) -> None:
    docker_stub.set_exit_code(1)

    result = run_validate_compose({"COMPOSE_INSTANCES": "core"})

    assert result.returncode != 0
    assert "✖ instância=\"core\"" in result.stderr
    assert f"files: {BASE_COMPOSE} {CORE_COMPOSE}" in result.stderr

    calls = docker_stub.read_calls()
    assert len(calls) == 1


def test_prefers_local_env_when_available(repo_copy: Path, docker_stub: DockerStub) -> None:
    docker_stub.set_exit_code(0)

    result = subprocess.run(
        [str(repo_copy / "scripts" / "validate_compose.sh")],
        capture_output=True,
        text=True,
        check=False,
        cwd=repo_copy,
        env={**os.environ, "COMPOSE_INSTANCES": "core"},
    )

    assert result.returncode == 0, result.stderr
    calls = docker_stub.read_calls()
    assert len(calls) == 1
    (call,) = calls
    assert call == [
        "compose",
        "--env-file",
        str(repo_copy / "env" / "local" / "core.env"),
        "-f",
        str(repo_copy / "compose" / "base.yml"),
        "-f",
        str(repo_copy / "compose" / "core.yml"),
        "config",
    ]


def test_missing_compose_file_in_temporary_copy(tmp_path: Path, docker_stub: DockerStub) -> None:
    repo_copy = tmp_path / "repo"
    shutil.copytree(REPO_ROOT / "compose", repo_copy / "compose")
    shutil.copytree(REPO_ROOT / "scripts", repo_copy / "scripts")
    shutil.copytree(REPO_ROOT / "env", repo_copy / "env")

    missing_instance = repo_copy / "compose" / "media.yml"
    missing_instance.unlink()

    result = subprocess.run(
        [str(repo_copy / "scripts" / "validate_compose.sh")],
        capture_output=True,
        text=True,
        check=False,
        cwd=repo_copy,
        env={**os.environ, "COMPOSE_INSTANCES": "media"},
    )

    assert result.returncode == 1
    assert "arquivo ausente" in result.stderr
    assert "media" in result.stderr
    assert docker_stub.read_calls() == []
