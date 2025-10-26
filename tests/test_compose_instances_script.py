from __future__ import annotations

import re
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = REPO_ROOT / "scripts" / "lib" / "compose_instances.sh"


def run_compose_instances(repo_root: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(SCRIPT_PATH), str(repo_root)],
        capture_output=True,
        text=True,
        check=False,
        cwd=repo_root,
    )


def find_declare_line(stdout: str, variable: str) -> str:
    pattern = re.compile(rf"^declare[^=]*\b{re.escape(variable)}=", re.MULTILINE)
    for line in stdout.splitlines():
        if pattern.search(line):
            return line
    raise AssertionError(f"Variable {variable} not found in output: {stdout!r}")


def parse_indexed_values(line: str) -> list[str]:
    matches = re.findall(r"\[(\d+)\]=\"([^\"]*)\"", line)
    return [value for _, value in sorted(((int(index), value) for index, value in matches))]


def parse_mapping(line: str) -> dict[str, str]:
    pattern = re.compile(r"\[([^\]]+)\]=(\$'[^']*'|\"[^\"]*\"|'[^']*')")
    mapping: dict[str, str] = {}

    for key, raw_value in pattern.findall(line):
        value = raw_value
        if value.startswith("$'"):
            inner = value[2:-1]
            value = bytes(inner, "utf-8").decode("unicode_escape")
        elif value.startswith("'") and value.endswith("'"):
            value = value[1:-1]
        elif value.startswith('"') and value.endswith('"'):
            value = value[1:-1]
        mapping[key] = value

    return mapping


def test_compose_instances_outputs_expected_metadata(repo_copy: Path) -> None:
    result = run_compose_instances(repo_copy)

    assert result.returncode == 0, result.stderr

    base_line = find_declare_line(result.stdout, "BASE_COMPOSE_FILE")
    base_match = re.search(r"=\"([^\"]+)\"", base_line)
    assert base_match is not None
    assert base_match.group(1) == "compose/base.yml"

    names_line = find_declare_line(result.stdout, "COMPOSE_INSTANCE_NAMES")
    assert parse_indexed_values(names_line) == ["core", "media"]

    files_line = find_declare_line(result.stdout, "COMPOSE_INSTANCE_FILES")
    files_map = parse_mapping(files_line)
    assert files_map == {
        "core": "compose/apps/app/core.yml",
        "media": "compose/apps/app/media.yml",
    }

    env_files_line = find_declare_line(result.stdout, "COMPOSE_INSTANCE_ENV_FILES")
    assert parse_mapping(env_files_line) == {
        "core": "env/local/core.env",
        "media": "env/media.example.env",
    }


def test_missing_base_file_causes_failure(repo_copy: Path) -> None:
    base_file = repo_copy / "compose" / "base.yml"
    base_file.unlink()

    result = run_compose_instances(repo_copy)

    assert result.returncode != 0
    assert "compose/base.yml" in result.stderr


def test_missing_env_files_causes_failure(repo_copy: Path) -> None:
    local_env = repo_copy / "env" / "local" / "core.env"
    template_env = repo_copy / "env" / "core.example.env"

    if local_env.exists():
        local_env.unlink()
    template_env.unlink()

    result = run_compose_instances(repo_copy)

    assert result.returncode != 0
    assert "Nenhum arquivo .env encontrado" in result.stderr
    assert "core" in result.stderr
