from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]


def test_compose_env_validation_falls_back_to_grep_when_rg_missing(
    tmp_path: Path,
) -> None:
    compose_file = tmp_path / "compose.yml"
    compose_file.write_text(
        "services:\n  app:\n    image: ${IMAGE}\n",
        encoding="utf-8",
    )

    tools_dir = tmp_path / "tools"
    tools_dir.mkdir()

    for tool in ("bash", "grep"):
        tool_path = shutil.which(tool)
        assert tool_path is not None
        (tools_dir / tool).symlink_to(tool_path)

    env = {**os.environ, "PATH": str(tools_dir)}
    script = f"""
set -euo pipefail
source "{REPO_ROOT}/scripts/_internal/lib/compose_env_validation.sh"
declare -a compose_files=("{compose_file}")
declare -A env_loaded=()
env_loaded[IMAGE]=1
declare -a env_chain=()
compose_env_validation__check "{tmp_path}" compose_files env_loaded env_chain ""
"""

    result = subprocess.run(
        ["/usr/bin/env", "bash", "-c", script],
        capture_output=True,
        text=True,
        check=False,
        env=env,
    )

    assert result.returncode == 0, result.stderr
