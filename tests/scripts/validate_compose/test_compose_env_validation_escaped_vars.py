from __future__ import annotations

import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]


def test_compose_env_validation_ignores_escaped_vars(tmp_path: Path) -> None:
    compose_file = tmp_path / "compose.yml"
    compose_file.write_text(
        "services:\n  app:\n    image: $${IMAGE}\n",
        encoding="utf-8",
    )

    script = f"""
set -euo pipefail
source "{REPO_ROOT}/scripts/_internal/lib/compose_env_validation.sh"
declare -a compose_files=("{compose_file}")
declare -A env_loaded=()
declare -a env_chain=()
compose_env_validation__check "{tmp_path}" compose_files env_loaded env_chain
"""

    result = subprocess.run(
        ["/usr/bin/env", "bash", "-c", script],
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
