import os
import shutil
import subprocess
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[3]
SCRIPT_PATH = REPO_ROOT / "scripts" / "check_structure.sh"


REQUIRED_PATHS = [
    "compose",
    "env",
    "scripts",
    "docs",
    "tests",
    ".github/workflows",
    "README.md",
    "docs/STRUCTURE.md",
    "scripts/check_structure.sh",
    "scripts/validate_compose.sh",
    ".github/workflows/template-quality.yml",
]


@pytest.mark.parametrize("flag", ["-h", "--help"])
def test_help_displays_usage(flag):
    result = subprocess.run(
        [str(SCRIPT_PATH), flag],
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0
    assert "Usage: scripts/check_structure.sh" in result.stdout


def test_script_succeeds_on_repository_root():
    result = subprocess.run(
        [str(SCRIPT_PATH)],
        capture_output=True,
        text=True,
        check=False,
        cwd=REPO_ROOT,
    )

    assert result.returncode == 0
    assert "Repository structure validated successfully." in result.stdout


def test_script_succeeds_from_subdirectory():
    result = subprocess.run(
        [str(SCRIPT_PATH)],
        capture_output=True,
        text=True,
        check=False,
        cwd=REPO_ROOT / "docs",
    )

    assert result.returncode == 0
    assert "Repository structure validated successfully." in result.stdout


@pytest.mark.parametrize("repo_copy", [(
    ".github",
    "docs",
)], indirect=True)
@pytest.mark.parametrize("missing_relative", REQUIRED_PATHS)
def test_missing_required_item_returns_error(repo_copy: Path, missing_relative: str) -> None:
    readme_copy = repo_copy / "README.md"
    if not readme_copy.exists():
        readme_copy.write_text((REPO_ROOT / "README.md").read_text(encoding="utf-8"), encoding="utf-8")

    missing_path = repo_copy / missing_relative
    if not missing_path.exists():
        source = REPO_ROOT / missing_relative
        if source.is_dir():
            shutil.copytree(source, missing_path)
        elif source.exists():
            missing_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, missing_path)
        else:
            pytest.fail(f"Path {missing_relative} was not copied to the temporary directory.")

    if missing_relative == "scripts":
        backup_dir = missing_path.with_name("scripts.bak")
        missing_path.rename(backup_dir)
        runner_dir = repo_copy / "scripts"
        runner_dir.mkdir(parents=True, exist_ok=True)
        runner_script = runner_dir / "check_structure.sh"
        runner_script.write_text(
            "#!/usr/bin/env bash\n"
            "set -euo pipefail\n"
            "script_dir=\"$(cd \"$(dirname \"${BASH_SOURCE[0]}\")\" && pwd)\"\n"
            "backup_dir=\"${script_dir}.bak\"\n"
            "rm -rf \"${script_dir}\"\n"
            "exec bash \"${backup_dir}/check_structure.sh\" \"$@\"\n",
            encoding="utf-8",
        )
        runner_script.chmod(0o755)
    elif missing_relative == "scripts/check_structure.sh":
        backup_script = missing_path.with_suffix(".bak")
        missing_path.rename(backup_script)
        missing_path.write_text(
            "#!/usr/bin/env bash\n"
            "set -euo pipefail\n"
            "rm -- \"$0\"\n"
            f"exec bash \"{backup_script}\" \"$@\"\n",
            encoding="utf-8",
        )
        missing_path.chmod(0o755)
    else:
        if missing_path.is_dir():
            shutil.rmtree(missing_path)
        else:
            missing_path.unlink()

    env = os.environ.copy()
    env.update({"CI": "true", "ROOT_DIR_OVERRIDE": str(repo_copy)})

    result = subprocess.run(
        [str(repo_copy / "scripts" / "check_structure.sh")],
        capture_output=True,
        text=True,
        check=False,
        cwd=repo_copy,
        env=env,
    )

    assert result.returncode == 1
    assert missing_relative in result.stderr
    assert "were not found" in result.stderr
