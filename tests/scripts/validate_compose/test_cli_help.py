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
        "Usage: scripts/validate_compose.sh",
        "",
        "Validates the repository instances, ensuring `docker compose config` succeeds",
        "for every combination of base files plus instance overrides.",
        "",
        "Positional arguments:",
        "  (none)",
        "",
        "Options:",
        "  --legacy-plan      Uses the dynamic combination of -f (legacy mode). Will be removed in a future release.",
        "",
        "Relevant environment variables:",
        "  DOCKER_COMPOSE_BIN  Override the docker compose command (for example: docker-compose).",
        "  COMPOSE_INSTANCES   Instances to validate (space- or comma-separated). Default: all.",
        "",
        "Examples:",
        "  scripts/validate_compose.sh",
        "  COMPOSE_INSTANCES=\"media\" scripts/validate_compose.sh",
        "",
    ]
    expected_help = "\n".join(expected_help_lines)

    assert result.returncode == 0
    assert result.stdout == expected_help
    assert result.stderr == ""
