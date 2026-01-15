import os
import sys
from pathlib import Path
from typing import Iterable

import yaml


PATH_PREFIXES = ("/", ".", "~", "$", "\\")


def looks_like_path(value: str) -> bool:
    if not value:
        return False
    if value.startswith(PATH_PREFIXES):
        return True
    if "/" in value or "\\" in value:
        return True
    return False


def normalize_source(raw: str, compose_dir: Path) -> str | None:
    if not raw:
        return None
    expanded = os.path.expandvars(raw)
    if "$" in expanded:
        return None
    expanded = os.path.expanduser(expanded)
    path = Path(expanded)
    if not path.is_absolute():
        path = (compose_dir / path).resolve()
    try:
        if path.exists() and path.is_file():
            return None
    except OSError:
        return None
    return str(path)


def iter_volume_sources(volumes: Iterable[object], compose_dir: Path) -> Iterable[str]:
    for entry in volumes:
        if isinstance(entry, str):
            raw = entry.strip()
            if not raw:
                continue
            parts = raw.split(":")
            if len(parts) < 2:
                continue
            source = parts[0].strip()
            if not looks_like_path(source):
                continue
            normalized = normalize_source(source, compose_dir)
            if normalized:
                yield normalized
            continue

        if isinstance(entry, dict):
            entry_type = (entry.get("type") or "").strip()
            source = entry.get("source") or entry.get("src") or ""
            if entry_type and entry_type != "bind":
                continue
            if not source:
                continue
            if not entry_type and not looks_like_path(source):
                continue
            normalized = normalize_source(source, compose_dir)
            if normalized:
                yield normalized


def collect_bind_mounts(files: Iterable[str]) -> list[str]:
    results: list[str] = []
    seen: set[str] = set()

    for file_path in files:
        path = Path(file_path)
        if not path.is_file():
            continue
        compose_dir = path.parent
        try:
            data = yaml.safe_load(path.read_text(encoding="utf-8"))
        except Exception:
            continue
        if not isinstance(data, dict):
            continue
        services = data.get("services")
        if not isinstance(services, dict):
            continue
        for service in services.values():
            if not isinstance(service, dict):
                continue
            volumes = service.get("volumes")
            if isinstance(volumes, list):
                for source in iter_volume_sources(volumes, compose_dir):
                    if source not in seen:
                        seen.add(source)
                        results.append(source)
            elif isinstance(volumes, dict):
                for source in iter_volume_sources(volumes.values(), compose_dir):
                    if source not in seen:
                        seen.add(source)
                        results.append(source)
    return results


def main() -> int:
    files = sys.argv[1:]
    if not files:
        return 0
    mounts = collect_bind_mounts(files)
    for path in mounts:
        print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
