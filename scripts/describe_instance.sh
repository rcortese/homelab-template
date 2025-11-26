#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

print_help() {
  cat <<'USAGE'
Usage: scripts/describe_instance.sh [--list] <instance> [--format <format>]

Generates a summary of services, ports, and volumes for the requested
instance from `docker compose config`, reusing the template conventions.

Positional arguments:
  instance            Instance name (e.g., core, media).

Flags:
  -h, --help          Show this help message and exit.
  --list              List available instances and exit.
  --format <format>   Output format. Accepted values: table (default), json.
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=lib/python_runtime.sh
source "${SCRIPT_DIR}/lib/python_runtime.sh"

FORMAT="table"
INSTANCE_NAME=""
LIST_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    print_help
    exit 0
    ;;
  --list)
    LIST_ONLY=true
    shift
    ;;
  --format)
    shift
    if [[ $# -eq 0 ]]; then
      echo "Error: --format requires a value (table or json)." >&2
      exit 1
    fi
    FORMAT="$1"
    shift
    ;;
  --format=*)
    FORMAT="${1#*=}"
    shift
    ;;
  --*)
    echo "Error: unknown flag '$1'." >&2
    exit 1
    ;;
  *)
    if [[ -z "$INSTANCE_NAME" ]]; then
      INSTANCE_NAME="$1"
    else
      echo "Error: extra parameters not recognized: '$1'." >&2
      exit 1
    fi
    shift
    ;;
  esac
done

if [[ "$LIST_ONLY" == true && -n "$INSTANCE_NAME" ]]; then
  echo "Error: --list cannot be combined with an instance name." >&2
  exit 1
fi

if [[ "$LIST_ONLY" == true ]]; then
  # shellcheck source=lib/compose_instances.sh
  source "$SCRIPT_DIR/lib/compose_instances.sh"

  if ! load_compose_instances "$REPO_ROOT"; then
    echo "Error: failed to load available instances." >&2
    exit 1
  fi

  echo "Available instances:"
  if [[ ${#COMPOSE_INSTANCE_NAMES[@]} -eq 0 ]]; then
    echo "  (no instances found)"
  else
    for name in "${COMPOSE_INSTANCE_NAMES[@]}"; do
      echo "  • $name"
    done
  fi
  exit 0
fi

if [[ -z "$INSTANCE_NAME" ]]; then
  echo "Error: provide the instance name." >&2
  print_help >&2
  exit 1
fi

FORMAT_LOWER="${FORMAT,,}"
if [[ "$FORMAT_LOWER" != "table" && "$FORMAT_LOWER" != "json" ]]; then
  echo "Error: invalid format '$FORMAT'. Use 'table' or 'json'." >&2
  exit 1
fi

# shellcheck source=lib/compose_defaults.sh
source "$SCRIPT_DIR/lib/compose_defaults.sh"

if ! setup_compose_defaults "$INSTANCE_NAME" "$REPO_ROOT"; then
  echo "Error: failed to build compose configuration for '$INSTANCE_NAME'." >&2
  exit 1
fi

declare -a CONFIG_CMD=("${COMPOSE_CMD[@]}")
CONFIG_CMD+=(config --format json)

tmp_stderr="$(mktemp)"
set +e
config_stdout="$("${CONFIG_CMD[@]}" 2>"$tmp_stderr")"
config_status=$?
set -e

if [[ $config_status -ne 0 ]]; then
  echo "Error: falha ao executar docker compose config." >&2
  if [[ -s "$tmp_stderr" ]]; then
    cat "$tmp_stderr" >&2
  fi
  rm -f "$tmp_stderr"
  exit $config_status
fi

if [[ -s "$tmp_stderr" ]]; then
  cat "$tmp_stderr" >&2
fi
rm -f "$tmp_stderr"

export DESCRIBE_INSTANCE_FORMAT="$FORMAT_LOWER"
export DESCRIBE_INSTANCE_NAME="$INSTANCE_NAME"
export DESCRIBE_INSTANCE_COMPOSE_FILES="${COMPOSE_FILES:-}"
export DESCRIBE_INSTANCE_EXTRA_FILES="${COMPOSE_EXTRA_FILES:-}"
export DESCRIBE_INSTANCE_REPO_ROOT="$REPO_ROOT"

python_runtime__run_stdin \
  "$REPO_ROOT" \
  "DESCRIBE_INSTANCE_FORMAT DESCRIBE_INSTANCE_NAME DESCRIBE_INSTANCE_COMPOSE_FILES DESCRIBE_INSTANCE_EXTRA_FILES DESCRIBE_INSTANCE_REPO_ROOT" \
  -- "$config_stdout" <<'PYTHON'
import json
import os
import sys
from pathlib import Path

format_arg = os.environ.get("DESCRIBE_INSTANCE_FORMAT", "table").strip().lower()
instance_name = os.environ.get("DESCRIBE_INSTANCE_NAME", "").strip()
compose_files_raw = os.environ.get("DESCRIBE_INSTANCE_COMPOSE_FILES", "")
extra_files_raw = os.environ.get("DESCRIBE_INSTANCE_EXTRA_FILES", "")
repo_root = Path(os.environ.get("DESCRIBE_INSTANCE_REPO_ROOT", ".")).resolve()

if not instance_name:
    print("Erro interno: instância não informada.", file=sys.stderr)
    sys.exit(1)

raw_config = sys.argv[1] if len(sys.argv) > 1 else ""
if not raw_config:
    raw_config = sys.stdin.read()

try:
    config = json.loads(raw_config)
except json.JSONDecodeError as exc:  # pragma: no cover - defensive path
    print(f"Erro ao interpretar saída do docker compose config: {exc}", file=sys.stderr)
    sys.exit(1)

services = config.get("services", {}) if isinstance(config, dict) else {}

repo_root_resolved = repo_root

def split_entries(raw: str) -> list[str]:
    tokens: list[str] = []
    for part in raw.replace("\n", " ").replace(",", " ").split():
        cleaned = part.strip()
        if cleaned:
            tokens.append(cleaned)
    return tokens


def normalize_for_compare(entry: str) -> str:
    path = Path(entry)
    if not path.is_absolute():
        path = (repo_root_resolved / path)
    return path.resolve(strict=False).as_posix()


def display_path(entry: str) -> str:
    path = Path(entry)
    if not path.is_absolute():
        return Path(entry).as_posix()
    resolved = path.resolve(strict=False)
    try:
        relative = resolved.relative_to(repo_root_resolved)
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

    left_parts: list[str] = []
    if host_ip:
        left_parts.append(str(host_ip))
    if published is not None:
        left_parts.append(str(published))

    left = ":".join(left_parts) if left_parts else ""
    right = str(target) if target is not None else ""

    pieces: list[str] = []
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


compose_entries = split_entries(compose_files_raw)
extra_entries = split_entries(extra_files_raw)
extra_normalized = {normalize_for_compare(entry) for entry in extra_entries}

compose_summary = []
for entry in compose_entries:
    normalized = normalize_for_compare(entry)
    compose_summary.append(
        {
            "path": display_path(entry),
            "is_extra": normalized in extra_normalized,
            "raw": entry,
        }
    )

extra_summary = [display_path(entry) for entry in extra_entries]

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

summary = {
    "instance": instance_name,
    "compose_files": compose_summary,
    "extra_overlays": extra_summary,
    "services": service_items,
}

if format_arg == "json":
    json.dump(summary, sys.stdout, ensure_ascii=False, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    sys.exit(0)

print(f"Instância: {instance_name}")
print("")
print("Arquivos Compose (-f):")
if compose_summary:
    for entry in compose_summary:
        marker = " (overlay extra)" if entry["is_extra"] else ""
        print(f"  • {entry['path']}{marker}")
else:
    print("  (nenhum arquivo encontrado)")

if extra_summary:
    print("")
    print("Overlays extras aplicados:")
    for overlay in extra_summary:
        print(f"  • {overlay}")

print("")
print("Serviços:")
if not service_items:
    print("  (nenhum serviço configurado)")
else:
    for item in service_items:
        print(f"  - {item['name']}")
        ports = item["ports"]
        if ports:
            print("      Portas publicadas:")
            for port in ports:
                print(f"        • {port}")
        else:
            print("      Portas publicadas: (nenhuma)")
        volumes = item["volumes"]
        if volumes:
            print("      Volumes montados:")
            for volume in volumes:
                print(f"        • {volume}")
        else:
            print("      Volumes montados: (nenhum)")

PYTHON
