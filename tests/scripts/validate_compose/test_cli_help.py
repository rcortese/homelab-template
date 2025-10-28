from __future__ import annotations

import subprocess
import pytest

from .utils import REPO_ROOT, SCRIPT_PATH


@pytest.mark.parametrize("flag", ["-h", "--help"])
def test_help_option_displays_usage_and_exits_successfully(flag: str) -> None:
    result = subprocess.run(
        [str(SCRIPT_PATH), flag],
        capture_output=True,
        text=True,
        check=False,
        cwd=REPO_ROOT,
    )

    expected_help_lines = [
        "Uso: scripts/validate_compose.sh",
        "",
        "Valida as instâncias definidas para o repositório garantindo que `docker compose config`",
        "execute com sucesso para cada combinação de arquivos base + instância.",
        "",
        "Argumentos posicionais:",
        "  (nenhum)",
        "",
        "Variáveis de ambiente relevantes:",
        "  DOCKER_COMPOSE_BIN  Sobrescreve o comando docker compose (ex.: docker-compose).",
        "  COMPOSE_INSTANCES   Lista de instâncias a validar (separadas por espaço ou vírgula). Default: todas.",
        "  COMPOSE_EXTRA_FILES Overlays extras aplicados após o override padrão (aceita espaços ou vírgulas).",
        "",
        "Exemplos:",
        "  scripts/validate_compose.sh",
        "  COMPOSE_INSTANCES=\"media\" scripts/validate_compose.sh",
        "  COMPOSE_EXTRA_FILES=\"compose/overlays/metrics.yml\" scripts/validate_compose.sh",
        "  COMPOSE_INSTANCES=\"media\" \\",
        "    COMPOSE_EXTRA_FILES=\"compose/overlays/logging.yml compose/overlays/metrics.yml\" \\",
        "    scripts/validate_compose.sh",
        "",
    ]
    expected_help = "\n".join(expected_help_lines)

    assert result.returncode == 0
    assert result.stdout == expected_help
    assert result.stderr == ""
