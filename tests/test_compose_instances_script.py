from __future__ import annotations

import re
import subprocess
from collections import defaultdict
from pathlib import Path

from tests.helpers.compose_instances import ComposeInstancesData


def _collect_compose_metadata(repo_root: Path) -> tuple[
    list[str],
    dict[str, list[str]],
    dict[str, list[str]],
    dict[str, str],
    dict[str, str],
    dict[str, str],
    dict[str, str],
]:
    base_rel = Path("compose/base.yml")
    assert (repo_root / base_rel).exists(), "Missing compose/base.yml in repo copy"

    apps_dir = repo_root / "compose" / "apps"
    assert apps_dir.is_dir(), "Missing compose/apps directory in repo copy"

    instance_files: dict[str, list[str]] = defaultdict(list)
    instance_app_names: dict[str, list[str]] = defaultdict(list)
    apps_without_overrides: list[str] = []
    app_base_files: dict[str, str] = {}

    for app_dir in sorted(path for path in apps_dir.iterdir() if path.is_dir()):
        base_file = app_dir / "base.yml"
        if base_file.exists():
            app_base_files[app_dir.name] = base_file.relative_to(repo_root).as_posix()

        app_files = list(sorted(app_dir.glob("*.yml"))) + list(sorted(app_dir.glob("*.yaml")))

        found_override = False
        for candidate in app_files:
            if candidate.stem == "base":
                continue

            found_override = True
            instance_name = candidate.stem
            rel_path = candidate.relative_to(repo_root).as_posix()

            if rel_path not in instance_files[instance_name]:
                instance_files[instance_name].append(rel_path)

            app_name = app_dir.name
            if app_name not in instance_app_names[instance_name]:
                instance_app_names[instance_name].append(app_name)

        if not found_override and base_file.exists():
            apps_without_overrides.append(app_dir.name)

    compose_dir = repo_root / "compose"
    top_level_candidates = list(sorted(compose_dir.glob("*.yml"))) + list(
        sorted(compose_dir.glob("*.yaml"))
    )
    for candidate in top_level_candidates:
        if candidate.stem == "base":
            continue

        instance_name = candidate.stem
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
        instance_app_names.setdefault(name, [])

    if apps_without_overrides:
        for app_name in apps_without_overrides:
            for name in instance_names:
                if app_name not in instance_app_names[name]:
                    instance_app_names[name].append(app_name)

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
        global_template = Path("env/common.example.env")

        if (repo_root / global_local).exists():
            entries.append(global_local.as_posix())
        elif (repo_root / global_template).exists():
            entries.append(global_template.as_posix())

        if local_exists:
            entries.append(local_rel.as_posix())
        elif template_exists:
            entries.append(template_rel.as_posix())
        else:
            raise AssertionError(
                f"Expected either {local_rel} or {template_rel} to exist for instance '{name}'"
            )

        env_file_map[name] = "\n".join(entries)

    return (
        instance_names,
        {name: list(paths) for name, paths in instance_files.items()},
        {name: list(apps) for name, apps in instance_app_names.items()},
        app_base_files,
        env_local_map,
        env_template_map,
        env_file_map,
    )


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

    (
        expected_names,
        expected_files_map,
        expected_app_names_map,
        expected_app_base_map,
        expected_env_local_map,
        expected_env_template_map,
        expected_env_files_map,
    ) = _collect_compose_metadata(repo_copy)

    base_line = find_declare_line(result.stdout, "BASE_COMPOSE_FILE")
    base_match = re.search(r"=\"([^\"]+)\"", base_line)
    assert base_match is not None
    assert base_match.group(1) == "compose/base.yml"

    names_line = find_declare_line(result.stdout, "COMPOSE_INSTANCE_NAMES")
    assert parse_indexed_values(names_line) == expected_names

    files_line = find_declare_line(result.stdout, "COMPOSE_INSTANCE_FILES")
    files_map = parse_mapping(files_line)
    assert {
        name: [entry for entry in value.splitlines() if entry]
        for name, value in files_map.items()
    } == expected_files_map

    app_names_line = find_declare_line(result.stdout, "COMPOSE_INSTANCE_APP_NAMES")
    app_names_map = parse_mapping(app_names_line)
    assert {
        name: [entry for entry in value.splitlines() if entry]
        for name, value in app_names_map.items()
    } == expected_app_names_map

    app_base_line = find_declare_line(result.stdout, "COMPOSE_APP_BASE_FILES")
    assert parse_mapping(app_base_line) == expected_app_base_map

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

    app_names_line = find_declare_line(result.stdout, "COMPOSE_INSTANCE_APP_NAMES")
    app_names_map = parse_mapping(app_names_line)

    files_line = find_declare_line(result.stdout, "COMPOSE_INSTANCE_FILES")
    files_map = parse_mapping(files_line)

    for instance in instance_names:
        apps = [entry for entry in app_names_map.get(instance, "").splitlines() if entry]
        for app in compose_instances_data.apps_without_overrides():
            assert app in apps

        overrides = [entry for entry in files_map.get(instance, "").splitlines() if entry]
        expected_overrides = compose_instances_data.instance_files.get(instance, [])
        for override in expected_overrides:
            assert override in overrides


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
