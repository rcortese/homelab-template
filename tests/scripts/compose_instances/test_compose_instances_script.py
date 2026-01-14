from __future__ import annotations

import re
import subprocess
from collections import defaultdict
from pathlib import Path

from tests.helpers.compose_instances import ComposeInstancesData


def _collect_compose_metadata(repo_root: Path) -> tuple[
    list[str],
    dict[str, list[str]],
    dict[str, str],
    dict[str, str],
    dict[str, str],
]:
    compose_dir = repo_root / "compose"
    instance_files: dict[str, list[str]] = defaultdict(list)

    compose_candidates = sorted(compose_dir.glob("docker-compose.*.yml"))
    for candidate in compose_candidates:
        name_part = candidate.name.replace("docker-compose.", "")
        instance_name = name_part.replace(".yml", "")
        if not instance_name or instance_name in {"base", "common"}:
            continue

        rel_path = candidate.relative_to(repo_root).as_posix()
        if rel_path not in instance_files[instance_name]:
            instance_files[instance_name].append(rel_path)

    known_instances = set(instance_files)
    env_dir = repo_root / "env"
    env_local_dir = env_dir / "local"

    for template in sorted(env_dir.glob("*.example.env")):
        name = template.name.replace(".example.env", "")
        if name and name != "common":
            known_instances.add(name)

    if env_local_dir.is_dir():
        for env_file in sorted(env_local_dir.glob("*.env")):
            name = env_file.stem
            if name and name != "common":
                known_instances.add(name)

    if not known_instances:
        raise AssertionError("No compose instances discovered in repo copy")

    instance_names = sorted(known_instances)

    for name in instance_names:
        instance_files.setdefault(name, [])

    env_local_map: dict[str, str] = {}
    env_template_map: dict[str, str] = {}
    env_file_map: dict[str, str] = {}

    for name in instance_names:
        local_rel = Path("env/local") / f"{name}.env"
        template_rel = Path("env") / f"{name}.example.env"

        local_exists = (repo_root / local_rel).exists()
        template_exists = (repo_root / template_rel).exists()

        env_local_map[name] = local_rel.as_posix() if local_exists else ""
        env_template_map[name] = template_rel.as_posix() if template_exists else ""

        entries: list[str] = []
        global_local = Path("env/local/common.env")

        if not (repo_root / global_local).exists():
            raise AssertionError(
                f"Expected {global_local} to exist to build the env chain for instance '{name}'"
            )
        entries.append(global_local.as_posix())

        if local_exists:
            entries.append(local_rel.as_posix())
        else:
            raise AssertionError(
                f"Expected {local_rel} to exist for instance '{name}'"
            )

        env_file_map[name] = "\n".join(entries)

    return (
        instance_names,
        {name: list(paths) for name, paths in instance_files.items()},
        env_local_map,
        env_template_map,
        env_file_map,
    )


REPO_ROOT = Path(__file__).resolve().parents[3]
SCRIPT_PATH = REPO_ROOT / "scripts" / "_internal" / "lib" / "compose_instances.sh"


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

    (
        expected_names,
        expected_files_map,
        expected_env_local_map,
        expected_env_template_map,
        expected_env_files_map,
    ) = _collect_compose_metadata(repo_copy)

    base_line = find_declare_line(result.stdout, "BASE_COMPOSE_FILE")
    base_match = re.search(r"=\"([^\"]*)\"", base_line)
    assert base_match is not None
    if (repo_copy / "compose" / "docker-compose.common.yml").exists():
        expected_base = "compose/docker-compose.common.yml"
    else:
        expected_base = ""
    assert base_match.group(1) == expected_base

    names_line = find_declare_line(result.stdout, "COMPOSE_INSTANCE_NAMES")
    assert parse_indexed_values(names_line) == expected_names

    files_line = find_declare_line(result.stdout, "COMPOSE_INSTANCE_FILES")
    files_map = parse_mapping(files_line)
    assert {
        name: [entry for entry in value.splitlines() if entry]
        for name, value in files_map.items()
    } == expected_files_map

    env_local_line = find_declare_line(result.stdout, "COMPOSE_INSTANCE_ENV_LOCAL")
    env_local_map = parse_mapping(env_local_line)
    assert env_local_map == expected_env_local_map

    env_templates_line = find_declare_line(result.stdout, "COMPOSE_INSTANCE_ENV_TEMPLATES")
    env_templates_map = parse_mapping(env_templates_line)
    assert env_templates_map == expected_env_template_map

    env_files_line = find_declare_line(result.stdout, "COMPOSE_INSTANCE_ENV_FILES")
    assert parse_mapping(env_files_line) == expected_env_files_map


def test_instances_include_apps_without_overrides(
    repo_copy: Path, compose_instances_data: ComposeInstancesData
) -> None:
    result = run_compose_instances(repo_copy)

    assert result.returncode == 0, result.stderr

    names_line = find_declare_line(result.stdout, "COMPOSE_INSTANCE_NAMES")
    instance_names = parse_indexed_values(names_line)

    files_line = find_declare_line(result.stdout, "COMPOSE_INSTANCE_FILES")
    files_map = parse_mapping(files_line)

    files_line = find_declare_line(result.stdout, "COMPOSE_INSTANCE_FILES")
    files_map = parse_mapping(files_line)

    for instance in instance_names:
        overrides = [entry for entry in files_map.get(instance, "").splitlines() if entry]
        expected_overrides = compose_instances_data.instance_files.get(instance, [])
        for override in expected_overrides:
            assert override in overrides


def test_apps_with_base_are_registered_for_all_instances(
    repo_copy: Path, compose_instances_data: ComposeInstancesData
) -> None:
    result = run_compose_instances(repo_copy)

    assert result.returncode == 0, result.stderr

    names_line = find_declare_line(result.stdout, "COMPOSE_INSTANCE_NAMES")
    instance_names = parse_indexed_values(names_line)

    files_line = find_declare_line(result.stdout, "COMPOSE_INSTANCE_FILES")
    files_map = parse_mapping(files_line)

    for instance in instance_names:
        overrides = [entry for entry in files_map.get(instance, "").splitlines() if entry]
        expected_overrides = compose_instances_data.instance_files.get(instance, [])
        for override in expected_overrides:
            assert override in overrides


def test_missing_base_file_is_allowed(repo_copy: Path) -> None:
    base_paths = [
        repo_copy / "compose" / "docker-compose.common.yml",
    ]
    for base_file in base_paths:
        if base_file.exists():
            base_file.unlink()

    result = run_compose_instances(repo_copy)

    assert result.returncode == 0, result.stderr

    base_line = find_declare_line(result.stdout, "BASE_COMPOSE_FILE")
    base_match = re.search(r"=\"([^\"]*)\"", base_line)
    assert base_match is not None
    assert base_match.group(1) == ""


def test_missing_instance_env_file_causes_failure(repo_copy: Path) -> None:
    local_env = repo_copy / "env" / "local" / "core.env"
    if local_env.exists():
        local_env.unlink()

    result = run_compose_instances(repo_copy)

    assert result.returncode != 0
    assert "Missing env/local/core.env" in result.stderr
    assert "cp env/core.example.env env/local/core.env" in result.stderr


def test_missing_common_env_file_causes_failure(repo_copy: Path) -> None:
    common_env = repo_copy / "env" / "local" / "common.env"
    if common_env.exists():
        common_env.unlink()

    result = run_compose_instances(repo_copy)

    assert result.returncode != 0
    assert "Missing env/local/common.env" in result.stderr
    assert "cp env/common.example.env env/local/common.env" in result.stderr
