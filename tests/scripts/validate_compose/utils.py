from __future__ import annotations

import json
import os
import subprocess
import textwrap
from dataclasses import dataclass
from collections.abc import Iterable, Sequence
from functools import lru_cache
from pathlib import Path

from tests.helpers.compose_instances import load_compose_instances_data

REPO_ROOT = Path(__file__).resolve().parents[3]
SCRIPT_PATH = REPO_ROOT / "scripts" / "validate_compose.sh"
BASE_COMPOSE_REL = Path("compose/base.yml")
BASE_COMPOSE = REPO_ROOT / BASE_COMPOSE_REL


@dataclass(frozen=True)
class InstanceMetadata:
    """Metadata discovered for a docker compose instance."""

    name: str
    app_names: tuple[str, ...]
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
        overrides_by_app: dict[str, list[Path]] = {}
        instance_level_overrides: list[Path] = []

        for entry, resolved in zip(self.override_files, override_paths):
            parts = entry.parts
            if len(parts) >= 3 and parts[0] == "compose" and parts[1] == "apps":
                app_name = parts[2]
                overrides_by_app.setdefault(app_name, []).append(resolved)
            else:
                instance_level_overrides.append(resolved)

        for override in instance_level_overrides:
            append_unique(override)

        for app_name in self.app_names:
            base_candidate = root / "compose" / "apps" / app_name / "base.yml"
            if base_candidate.exists():
                append_unique(base_candidate)
            for override in overrides_by_app.get(app_name, []):
                append_unique(override)

        for override in override_paths:
            append_unique(override)

        return files

    def override_files_for_app(self, app_name: str) -> Iterable[Path]:
        for override in self.override_files:
            parts = override.parts
            if len(parts) >= 3 and parts[0] == "compose" and parts[1] == "apps" and parts[2] == app_name:
                yield override


def run_validate_compose(env: dict[str, str], cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(SCRIPT_PATH)],
        capture_output=True,
        text=True,
        check=False,
        cwd=cwd or REPO_ROOT,
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
        expected_compose_call(env_files, files, "config", "--output", str(output_file)),
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
    instances = load_compose_instances_data(repo_root)

    metadata: list[InstanceMetadata] = []

    for name in sorted(instances.instance_names):
        override_files = tuple(Path(entry) for entry in instances.instance_files.get(name, ()))
        env_local_raw = instances.env_local_map.get(name)
        env_template_raw = instances.env_template_map.get(name)

        env_local = Path(env_local_raw) if env_local_raw else None
        env_template = Path(env_template_raw) if env_template_raw else None

        env_entries = [Path(entry) for entry in instances.env_files_map.get(name, ())]

        env_file: Path | None
        if env_local is not None:
            env_file = env_local
        else:
            env_file = env_template

        metadata.append(
            InstanceMetadata(
                name=name,
                app_names=tuple(instances.instance_app_names.get(name, ())),
                override_files=override_files,
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
