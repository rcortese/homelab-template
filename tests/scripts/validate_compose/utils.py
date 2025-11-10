from __future__ import annotations

import os
import subprocess
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


def _discover_instance_metadata(repo_root: Path) -> tuple[InstanceMetadata, ...]:
    compose_dir = repo_root / "compose"
    apps_dir = compose_dir / "apps"
    if not apps_dir.is_dir():  # pragma: no cover - defensive
        raise FileNotFoundError(f"Diretório de aplicações não encontrado: {apps_dir}")

    instance_files: dict[str, list[Path]] = {}
    instance_app_names: dict[str, list[str]] = {}
    apps_without_overrides: list[str] = []

    for app_dir in sorted(path for path in apps_dir.iterdir() if path.is_dir()):
        base_override = app_dir / "base.yml"
        has_base = base_override.exists()

        app_files = list(sorted(app_dir.glob("*.yml"))) + list(sorted(app_dir.glob("*.yaml")))
        found_override = False

        for candidate in app_files:
            if candidate.stem == "base":
                continue

            found_override = True
            instance_name = candidate.stem
            rel_path = candidate.relative_to(repo_root)

            instance_files.setdefault(instance_name, [])
            if rel_path not in instance_files[instance_name]:
                instance_files[instance_name].append(rel_path)

            instance_app_names.setdefault(instance_name, [])
            if app_dir.name not in instance_app_names[instance_name]:
                instance_app_names[instance_name].append(app_dir.name)

        if not found_override and has_base:
            apps_without_overrides.append(app_dir.name)

    top_level_candidates = list(sorted(compose_dir.glob("*.yml"))) + list(
        sorted(compose_dir.glob("*.yaml"))
    )
    for candidate in top_level_candidates:
        if candidate.stem == "base":
            continue

        instance_name = candidate.stem
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
        raise ValueError("Nenhuma instância encontrada em compose/apps ou env.")

    instance_names = sorted(known_instances)

    for name in instance_names:
        instance_files.setdefault(name, [])
        instance_app_names.setdefault(name, [])

    if apps_without_overrides:
        for app_name in apps_without_overrides:
            for name in instance_names:
                if app_name not in instance_app_names[name]:
                    instance_app_names[name].append(app_name)

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
                app_names=tuple(instance_app_names.get(name, ())),
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
    "get_instance_metadata_map",
    "get_instance_names",
    "load_instance_metadata",
    "run_validate_compose",
]
