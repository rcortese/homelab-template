from __future__ import annotations

import json
import os
import subprocess
import textwrap
from dataclasses import dataclass
from collections.abc import Iterable, Sequence
from functools import lru_cache
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
SCRIPT_PATH = REPO_ROOT / "scripts" / "validate_compose.sh"
BASE_COMPOSE_REL = Path("compose/base.yml")
BASE_COMPOSE = REPO_ROOT / BASE_COMPOSE_REL


@dataclass(frozen=True)
class InstanceMetadata:
    """Metadata discovered for a docker compose instance."""

    name: str
    override_files: tuple[Path, ...]
    env_file: Path | None
    env_local: Path | None
    env_template: Path | None
    env_chain: tuple[Path, ...]

    def resolved_env_file(self, repo_root: Path | None = None) -> Path | None:
        root = Path(repo_root or REPO_ROOT)
        return None if self.env_file is None else root / self.env_file

    def resolved_env_chain(self, repo_root: Path | None = None) -> tuple[Path, ...]:
        root = Path(repo_root or REPO_ROOT)
        return tuple(root / entry for entry in self.env_chain)

    def compose_files(self, repo_root: Path | None = None) -> list[Path]:
        root = Path(repo_root or REPO_ROOT)
        files: list[Path] = []
        seen: set[Path] = set()

        def append_unique(candidate: Path) -> None:
            if candidate not in seen:
                files.append(candidate)
                seen.add(candidate)

        base_candidate = root / BASE_COMPOSE_REL
        if base_candidate.exists():
            append_unique(base_candidate)

        override_paths = [root / entry for entry in self.override_files]
        for override in override_paths:
            append_unique(override)

        return files

    def override_files_for_app(self, app_name: str) -> Iterable[Path]:
        for override in self.override_files:
            parts = override.parts
            if len(parts) >= 3 and parts[0] == "compose" and parts[1] == "apps" and parts[2] == app_name:
                yield override


def run_validate_compose(env: dict[str, str], cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    script_root = Path(cwd) if cwd is not None else REPO_ROOT
    script_path = script_root / "scripts" / "validate_compose.sh"
    return subprocess.run(
        [str(script_path)],
        capture_output=True,
        text=True,
        check=False,
        cwd=script_root,
        env={**os.environ, **env},
    )


def expected_compose_call(
    env_files: Path | Sequence[Path] | None, files: Iterable[Path], *args: str
) -> list[str]:
    cmd: list[str] = ["compose"]
    if env_files is not None:
        if isinstance(env_files, Path):
            entries: Sequence[Path] = (env_files,)
        else:
            entries = env_files
        for env in entries:
            cmd.extend(["--env-file", str(env)])
    for file in files:
        cmd.extend(["-f", str(file)])
    cmd.extend(args)
    return cmd


def expected_consolidated_calls(
    env_files: Path | Sequence[Path] | None, files: Iterable[Path], output_file: Path
) -> list[list[str]]:
    return [
        expected_compose_call(env_files, files, "config"),
        expected_compose_call(env_files, [output_file], "config", "-q"),
    ]


def load_app_data_from_deploy_context(repo_root: Path, instance: str) -> dict[str, str]:
    script = textwrap.dedent(
        f"""
        set -euo pipefail
        source {json.dumps(str(repo_root / 'scripts' / 'lib' / 'deploy_context.sh'))}
        if ! context_out=$(build_deploy_context {json.dumps(str(repo_root))} {json.dumps(instance)}); then
          exit 1
        fi
        eval "$context_out"
        printf 'APP_DATA_DIR=%s\\n' "${{DEPLOY_CONTEXT[APP_DATA_DIR]}}"
        printf 'APP_DATA_DIR_MOUNT=%s\\n' "${{DEPLOY_CONTEXT[APP_DATA_DIR_MOUNT]}}"
        """
    ).strip()

    result = subprocess.run(
        ["bash", "-c", script],
        capture_output=True,
        text=True,
        check=False,
        cwd=repo_root,
        env={**os.environ},
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"Failed to build deploy context for instance '{instance}': {result.stderr}"
        )

    context: dict[str, str] = {}
    for line in result.stdout.splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        context[key] = value

    for key in ("APP_DATA_DIR", "APP_DATA_DIR_MOUNT"):
        context.setdefault(key, "")

    return context


def _discover_instance_metadata(repo_root: Path) -> tuple[InstanceMetadata, ...]:
    compose_dir = repo_root / "compose"

    instance_files: dict[str, list[Path]] = {}
    top_level_candidates = list(sorted(compose_dir.glob("docker-compose.*.yml"))) + list(
        sorted(compose_dir.glob("docker-compose.*.yaml"))
    )
    for candidate in top_level_candidates:
        instance_name = candidate.stem.replace("docker-compose.", "", 1)
        if not instance_name or instance_name == "base":
            continue

        rel_path = candidate.relative_to(repo_root)

        instance_files.setdefault(instance_name, [])
        if rel_path not in instance_files[instance_name]:
            instance_files[instance_name].append(rel_path)

    known_instances: set[str] = set(instance_files)
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
        raise ValueError("No instances found in compose or env.")

    instance_names = sorted(known_instances)

    for name in instance_names:
        instance_files.setdefault(name, [])

    metadata: list[InstanceMetadata] = []

    for name in instance_names:
        local_rel = Path("env/local") / f"{name}.env"
        template_rel = Path("env") / f"{name}.example.env"

        env_local = local_rel if (repo_root / local_rel).exists() else None
        env_template = template_rel if (repo_root / template_rel).exists() else None

        env_entries: list[Path] = []
        global_local = Path("env/local/common.env")
        global_template = Path("env/common.example.env")

        if (repo_root / global_local).exists():
            env_entries.append(global_local)
        elif (repo_root / global_template).exists():
            env_entries.append(global_template)

        env_file: Path | None
        if env_local is not None:
            env_file = env_local
            env_entries.append(env_local)
        else:
            env_file = env_template
            if env_template is not None:
                env_entries.append(env_template)

        metadata.append(
            InstanceMetadata(
                name=name,
                override_files=tuple(instance_files.get(name, ())),
                env_file=env_file,
                env_local=env_local,
                env_template=env_template,
                env_chain=tuple(env_entries),
            )
        )

    return tuple(metadata)


@lru_cache(maxsize=None)
def _load_instance_metadata_cached(repo_root: str) -> tuple[InstanceMetadata, ...]:
    return _discover_instance_metadata(Path(repo_root))


def load_instance_metadata(repo_root: Path | None = None) -> tuple[InstanceMetadata, ...]:
    root = Path(repo_root or REPO_ROOT)
    return _load_instance_metadata_cached(str(root))


def get_instance_metadata_map(repo_root: Path | None = None) -> dict[str, InstanceMetadata]:
    return {metadata.name: metadata for metadata in load_instance_metadata(repo_root)}


def get_instance_names(repo_root: Path | None = None) -> list[str]:
    return [metadata.name for metadata in load_instance_metadata(repo_root)]


__all__ = [
    "BASE_COMPOSE",
    "InstanceMetadata",
    "REPO_ROOT",
    "SCRIPT_PATH",
    "expected_compose_call",
    "expected_consolidated_calls",
    "get_instance_metadata_map",
    "get_instance_names",
    "load_instance_metadata",
    "run_validate_compose",
]
