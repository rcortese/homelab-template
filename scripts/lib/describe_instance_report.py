import json
import os
import sys
from pathlib import Path
from typing import Any, Dict, List


def split_entries(raw: str) -> List[str]:
    tokens: List[str] = []
    for part in raw.replace("\n", " ").replace(",", " ").split():
        cleaned = part.strip()
        if cleaned:
            tokens.append(cleaned)
    return tokens


def normalize_for_compare(entry: str, repo_root: Path) -> str:
    path = Path(entry)
    if not path.is_absolute():
        path = repo_root / path
    return path.resolve(strict=False).as_posix()


def display_path(entry: str, repo_root: Path) -> str:
    path = Path(entry)
    if not path.is_absolute():
        return Path(entry).as_posix()
    resolved = path.resolve(strict=False)
    try:
        relative = resolved.relative_to(repo_root)
        return relative.as_posix()
    except ValueError:
        return resolved.as_posix()


def format_port(port: object) -> str:
    if isinstance(port, str):
        return port
    if not isinstance(port, dict):
        return str(port)

    target = port.get("target")
    published = port.get("published")
    protocol = port.get("protocol") or "tcp"
    mode = port.get("mode")
    host_ip = port.get("host_ip")

    left_parts: List[str] = []
    if host_ip:
        left_parts.append(str(host_ip))
    if published is not None:
        left_parts.append(str(published))

    left = ":".join(left_parts) if left_parts else ""
    right = str(target) if target is not None else ""

    pieces: List[str] = []
    if left:
        pieces.append(left)
    if right:
        if pieces:
            pieces.append("->")
        pieces.append(right)

    result = " ".join(pieces) if pieces else (right or left or "")
    if result:
        result = f"{result}/{protocol}"
    else:
        result = f"{target}/{protocol}" if target is not None else f"{protocol}"

    if mode and mode not in {"ingress"}:
        result = f"{result} ({mode})"

    return result


def format_volume(volume: object) -> str:
    if isinstance(volume, str):
        return volume
    if not isinstance(volume, dict):
        return str(volume)

    source = volume.get("source")
    target = volume.get("target")

    base: str
    if source and target:
        base = f"{source} -> {target}"
    elif target:
        base = str(target)
    elif source:
        base = str(source)
    else:
        base = ""

    details = {k: v for k, v in volume.items() if k not in {"source", "target"}}
    if not details:
        return base or json.dumps(volume, ensure_ascii=False, sort_keys=True)

    detail_items = []
    for key in sorted(details):
        value = details[key]
        if isinstance(value, dict):
            detail_items.append(f"{key}={json.dumps(value, ensure_ascii=False, sort_keys=True)}")
        else:
            detail_items.append(f"{key}={value}")

    detail_str = ", ".join(detail_items)
    if base:
        return f"{base} ({detail_str})"
    return detail_str


def build_summary(
    config: Dict[str, Any],
    instance_name: str,
    compose_files_raw: str,
    extra_files_raw: str,
    repo_root: Path,
) -> Dict[str, Any]:
    services = config.get("services", {}) if isinstance(config, dict) else {}

    compose_entries = split_entries(compose_files_raw)
    extra_entries = split_entries(extra_files_raw)
    extra_normalized = {normalize_for_compare(entry, repo_root) for entry in extra_entries}

    compose_summary = []
    for entry in compose_entries:
        normalized = normalize_for_compare(entry, repo_root)
        compose_summary.append(
            {
                "path": display_path(entry, repo_root),
                "is_extra": normalized in extra_normalized,
                "raw": entry,
            }
        )

    extra_summary = [display_path(entry, repo_root) for entry in extra_entries]

    service_items = []
    for service_name in sorted(services):
        service = services[service_name]
        if not isinstance(service, dict):
            continue
        ports = [format_port(port) for port in service.get("ports", [])]
        volumes = [format_volume(volume) for volume in service.get("volumes", [])]
        service_items.append(
            {
                "name": service_name,
                "ports": ports,
                "volumes": volumes,
            }
        )

    return {
        "instance": instance_name,
        "compose_files": compose_summary,
        "extra_files": extra_summary,
        "services": service_items,
    }


def render_table(summary: Dict[str, Any]) -> None:
    instance_name = summary.get("instance", "")
    compose_summary = summary.get("compose_files", [])
    extra_summary = summary.get("extra_files", [])
    service_items = summary.get("services", [])

    print(f"Instance: {instance_name}")
    print("")
    print("Compose files (-f):")
    if compose_summary:
        for entry in compose_summary:
            marker = " (extra file)" if entry.get("is_extra") else ""
            print(f"  • {entry.get('path', '')}{marker}")
    else:
        print("  (no files found)")

    if extra_summary:
        print("")
        print("Extra compose files applied:")
        for extra_file in extra_summary:
            print(f"  • {extra_file}")

    print("")
    print("Services:")
    if not service_items:
        print("  (no services configured)")
    else:
        for item in service_items:
            print(f"  - {item.get('name', '')}")
            ports = item.get("ports", [])
            if ports:
                print("      Published ports:")
                for port in ports:
                    print(f"        • {port}")
            else:
                print("      Published ports: (none)")
            volumes = item.get("volumes", [])
            if volumes:
                print("      Mounted volumes:")
                for volume in volumes:
                    print(f"        • {volume}")
            else:
                print("      Mounted volumes: (none)")


def main(
    raw_config: str,
    format: str,
    instance: str,
    compose_files: str,
    extra_files: str,
    repo_root: str,
) -> int:
    format_arg = (format or "table").strip().lower()
    instance_name = (instance or "").strip()
    repo_root_resolved = Path(repo_root or ".").resolve()

    if not instance_name:
        print("Internal error: instance not provided.", file=sys.stderr)
        return 1

    if not raw_config:
        print("Error: missing docker compose config payload.", file=sys.stderr)
        return 1

    try:
        config = json.loads(raw_config)
    except json.JSONDecodeError as exc:  # pragma: no cover - defensive path
        print(f"Error parsing docker compose config output: {exc}", file=sys.stderr)
        return 1

    summary = build_summary(config, instance_name, compose_files, extra_files, repo_root_resolved)

    if format_arg == "json":
        json.dump(summary, sys.stdout, ensure_ascii=False, indent=2, sort_keys=True)
        sys.stdout.write("\n")
        return 0

    render_table(summary)
    return 0


if __name__ == "__main__":
    raw_config_arg = sys.argv[1] if len(sys.argv) > 1 else ""
    if not raw_config_arg:
        raw_config_arg = sys.stdin.read()

    sys.exit(
        main(
            raw_config=raw_config_arg,
            format=os.environ.get("DESCRIBE_INSTANCE_FORMAT", "table"),
            instance=os.environ.get("DESCRIBE_INSTANCE_NAME", ""),
            compose_files=os.environ.get("DESCRIBE_INSTANCE_COMPOSE_FILES", ""),
            extra_files=os.environ.get("DESCRIBE_INSTANCE_EXTRA_FILES", ""),
            repo_root=os.environ.get("DESCRIBE_INSTANCE_REPO_ROOT", "."),
        )
    )
