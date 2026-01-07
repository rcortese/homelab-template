#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Usage: scripts/check_health.sh [--format text|json] [--output <file>] [instance]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ORIGINAL_PWD="${PWD:-}"
CHANGED_TO_REPO_ROOT=false
# shellcheck source=./lib/python_runtime.sh
source "${SCRIPT_DIR}/lib/python_runtime.sh"

OUTPUT_FORMAT="text"
OUTPUT_FILE=""

if [[ "$ORIGINAL_PWD" != "$REPO_ROOT" ]]; then
  cd "$REPO_ROOT"
  CHANGED_TO_REPO_ROOT=true
fi

REPO_ROOT="$(pwd)"

# shellcheck source=./lib/compose_command.sh
source "$SCRIPT_DIR/lib/compose_command.sh"

# shellcheck source=./lib/env_helpers.sh
source "$SCRIPT_DIR/lib/env_helpers.sh"

# shellcheck source=./lib/env_file_chain.sh
source "$SCRIPT_DIR/lib/env_file_chain.sh"

print_help() {
  cat <<'EOF'
Usage: scripts/check_health.sh [options] [instance]

Checks service status for an instance and prints logs for the monitored services.

Options:
  --format {text,json}  Defines the output format (default: text).
  --output <file>       Writes the final output to the provided path in addition to stdout.

Examples:
  scripts/check_health.sh core
  scripts/check_health.sh --format json --output status.json media
EOF
}

POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    print_help
    exit 0
    ;;
  --format)
    if [[ $# -lt 2 ]]; then
      echo "Error: --format requer um valor (text|json)." >&2
      exit 2
    fi
    format_value="$2"
    case "$format_value" in
    text | json)
      OUTPUT_FORMAT="$format_value"
      ;;
    *)
      echo "Error: invalid value for --format: $format_value" >&2
      exit 2
      ;;
    esac
    shift 2
    continue
    ;;
  --format=*)
    format_value="${1#*=}"
    case "$format_value" in
    text | json)
      OUTPUT_FORMAT="$format_value"
      ;;
    *)
      echo "Error: invalid value for --format: $format_value" >&2
      exit 2
      ;;
    esac
    shift
    continue
    ;;
  --output)
    if [[ $# -lt 2 ]]; then
      echo "Error: --output requires a valid path." >&2
      exit 2
    fi
    OUTPUT_FILE="$2"
    shift 2
    continue
    ;;
  --output=*)
    OUTPUT_FILE="${1#*=}"
    shift
    continue
    ;;
  --)
    shift
    while [[ $# -gt 0 ]]; do
      POSITIONAL_ARGS+=("$1")
      shift
    done
    break
    ;;
  -*)
    echo "Error: unknown option: $1" >&2
    exit 2
    ;;
  *)
    POSITIONAL_ARGS+=("$1")
    shift
    ;;
  esac
done

if [[ ${#POSITIONAL_ARGS[@]} -gt 0 ]]; then
  set -- "${POSITIONAL_ARGS[@]}"
else
  set --
fi

COMPOSE_ROOT_FILE="$REPO_ROOT/docker-compose.yml"
INSTANCE_NAME="${1:-}"

unset COMPOSE_FILES
unset COMPOSE_EXTRA_FILES

declare -a DOCKER_COMPOSE_CMD=()
compose_resolve_command DOCKER_COMPOSE_CMD
compose_status=$?
if ((compose_status != 0)); then
  exit "$compose_status"
fi

if [[ -n "$INSTANCE_NAME" ]]; then
  declare -a BUILD_COMPOSE_CMD=("$SCRIPT_DIR/build_compose_file.sh" --instance "$INSTANCE_NAME")

  if ! "${BUILD_COMPOSE_CMD[@]}" >/dev/null; then
    echo "Error: failed to generate consolidated docker-compose.yml." >&2
    exit 1
  fi
else
  if [[ ! -f "$COMPOSE_ROOT_FILE" ]]; then
    echo "Error: docker-compose.yml not found; run scripts/build_compose_file.sh --instance <name>." >&2
    exit 1
  fi
fi

COMPOSE_CMD=("${DOCKER_COMPOSE_CMD[@]}" -f "$COMPOSE_ROOT_FILE")

if [[ -z "${HEALTH_SERVICES:-}" ]]; then
  if [[ -f "$REPO_ROOT/.env" ]]; then
    load_env_pairs "$REPO_ROOT/.env" HEALTH_SERVICES || true
  fi
fi

mapfile -t LOG_TARGETS < <(env_file_chain__parse_list "${HEALTH_SERVICES:-}") || true

if [[ ${#LOG_TARGETS[@]} -eq 0 ]]; then
  :
fi

primary_targets=("${LOG_TARGETS[@]}")

append_real_service_targets() {
  declare -A __log_targets_seen=()
  local __service
  for __service in "${LOG_TARGETS[@]}"; do
    __log_targets_seen["$__service"]=1
  done

  local compose_services_output
  if compose_services_output="$("${COMPOSE_CMD[@]}" config --services 2>/dev/null)"; then
    local compose_service
    while IFS= read -r compose_service; do
      if [[ -z "$compose_service" ]]; then
        continue
      fi
      if [[ -n "${__log_targets_seen["$compose_service"]:-}" ]]; then
        continue
      fi
      LOG_TARGETS+=("$compose_service")
      __log_targets_seen["$compose_service"]=1
    done <<<"$compose_services_output"
  fi

  unset __log_targets_seen
  unset __service
}

append_real_service_targets
unset -f append_real_service_targets

auto_targets=()
if ((${#LOG_TARGETS[@]} > ${#primary_targets[@]})); then
  auto_targets=("${LOG_TARGETS[@]:${#primary_targets[@]}}")
fi
ALL_LOG_TARGETS=("${primary_targets[@]}" "${auto_targets[@]}")
LOG_TARGETS=("${primary_targets[@]}")

if [[ ${#LOG_TARGETS[@]} -eq 0 ]]; then
  if [[ ${#auto_targets[@]} -gt 0 ]]; then
    LOG_TARGETS=("${auto_targets[@]}")
    primary_targets=("${LOG_TARGETS[@]}")
    ALL_LOG_TARGETS=("${LOG_TARGETS[@]}")
    auto_targets=()
  else
    echo "Error: no services were found for log collection." >&2
    echo "       Configure HEALTH_SERVICES or ensure the Compose manifests declare valid services." >&2
    exit 1
  fi
fi

compose_ps_output="$("${COMPOSE_CMD[@]}" ps)"
compose_ps_json=""
if [[ "$OUTPUT_FORMAT" == "json" ]]; then
  if compose_ps_json_candidate="$("${COMPOSE_CMD[@]}" ps --format json 2>/dev/null)"; then
    compose_ps_json="$compose_ps_json_candidate"
  fi
fi

if [[ "$OUTPUT_FORMAT" == "text" ]]; then
  echo "[*] Containers:"
  printf '%s\n' "$compose_ps_output"
  echo
  echo "[*] Recent logs for monitored services:"
fi

log_success=false
failed_services=()
declare -A SERVICE_LOGS=()
declare -A SERVICE_STATUSES=()

for service in "${LOG_TARGETS[@]}"; do
  if [[ -z "$service" ]]; then
    continue
  fi
  if service_output="$("${COMPOSE_CMD[@]}" logs --tail=50 "$service" 2>&1)"; then
    SERVICE_LOGS["$service"]="$service_output"
    SERVICE_STATUSES["$service"]="ok"
    log_success=true
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
      printf '%s\n' "$service_output"
    fi
  else
    SERVICE_LOGS["$service"]="$service_output"
    SERVICE_STATUSES["$service"]="error"
    printf '%s\n' "$service_output" >&2
    failed_services+=("$service")
  fi
done

if [[ ${#auto_targets[@]} -gt 0 ]]; then
  for service in "${auto_targets[@]}"; do
    if [[ -z "$service" ]]; then
      continue
    fi
    if service_output="$("${COMPOSE_CMD[@]}" logs --tail=50 "$service" 2>&1)"; then
      SERVICE_LOGS["$service"]="$service_output"
      SERVICE_STATUSES["$service"]="ok"
      log_success=true
      if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        printf '%s\n' "$service_output"
      fi
    else
      SERVICE_LOGS["$service"]="$service_output"
      SERVICE_STATUSES["$service"]="error"
      printf '%s\n' "$service_output" >&2
      failed_services+=("$service")
    fi
  done
fi

if [[ "$log_success" == false ]]; then
  printf 'Failed to retrieve logs for services: %s\n' "${ALL_LOG_TARGETS[*]}" >&2
  exit 1
fi

if [[ ${#failed_services[@]} -gt 0 ]]; then
  printf 'Warning: Failed to retrieve logs for services: %s\n' "${failed_services[*]}" >&2
fi

if [[ "$OUTPUT_FORMAT" == "json" ]]; then
  COMPOSE_PS_TEXT="$compose_ps_output"
  COMPOSE_PS_JSON="$compose_ps_json"
  PRIMARY_LOG_SERVICES="${primary_targets[*]}"
  AUTO_LOG_SERVICES="${auto_targets[*]}"
  ALL_LOG_SERVICES="${ALL_LOG_TARGETS[*]}"
  FAILED_SERVICES_STR="${failed_services[*]:-}"
  LOG_SUCCESS_FLAG="$log_success"

  declare -a __service_payload_lines=()
  for service in "${ALL_LOG_TARGETS[@]}"; do
    status="${SERVICE_STATUSES[$service]:-skipped}"
    log_value="${SERVICE_LOGS[$service]:-}"
    encoded_log="$(printf '%s' "$log_value" | base64 | tr -d '\n')"
    __service_payload_lines+=("$service::${status}::${encoded_log}")
  done
  if ((${#__service_payload_lines[@]} > 0)); then
    SERVICE_PAYLOAD="$(printf '%s\n' "${__service_payload_lines[@]}")"
  else
    SERVICE_PAYLOAD=""
  fi
  export COMPOSE_PS_TEXT COMPOSE_PS_JSON PRIMARY_LOG_SERVICES AUTO_LOG_SERVICES ALL_LOG_SERVICES FAILED_SERVICES_STR \
    LOG_SUCCESS_FLAG SERVICE_PAYLOAD INSTANCE_NAME

  json_payload="$(
    python_runtime__run_stdin \
      "$REPO_ROOT" \
      "COMPOSE_PS_TEXT COMPOSE_PS_JSON PRIMARY_LOG_SERVICES AUTO_LOG_SERVICES ALL_LOG_SERVICES FAILED_SERVICES_STR LOG_SUCCESS_FLAG SERVICE_PAYLOAD INSTANCE_NAME" \
      -- <<'PYTHON'
import base64
import json
import os

compose_ps_text = os.environ.get("COMPOSE_PS_TEXT", "")
compose_ps_json_raw = os.environ.get("COMPOSE_PS_JSON", "")
primary_targets = [x for x in os.environ.get("PRIMARY_LOG_SERVICES", "").split() if x]
auto_targets = [x for x in os.environ.get("AUTO_LOG_SERVICES", "").split() if x]
all_targets = [x for x in os.environ.get("ALL_LOG_SERVICES", "").split() if x]
failed_services = [x for x in os.environ.get("FAILED_SERVICES_STR", "").split() if x]
log_success = os.environ.get("LOG_SUCCESS_FLAG", "false").lower() == "true"
instance = os.environ.get("INSTANCE_NAME", "") or None

services_entries = []
for line in os.environ.get("SERVICE_PAYLOAD", "").splitlines():
    if not line:
        continue
    parts = line.split("::", 2)
    if len(parts) != 3:
        continue
    name, status, encoded = parts
    log_text = ""
    log_b64 = encoded if encoded else None
    if encoded:
        try:
            log_text = base64.b64decode(encoded.encode()).decode("utf-8", errors="replace")
        except Exception:
            log_text = ""
    entry = {
        "service": name,
        "status": status,
        "log": log_text,
    }
    if log_b64 is not None:
        entry["log_b64"] = log_b64
    services_entries.append(entry)

compose_section = {"raw": compose_ps_text}
if compose_ps_json_raw:
    try:
        compose_section["parsed"] = json.loads(compose_ps_json_raw)
    except json.JSONDecodeError:
        compose_section["parsed_error"] = "invalid_json"
        compose_section["parsed_raw"] = compose_ps_json_raw

summary_status = "ok" if not failed_services else "degraded"

result = {
    "format": "json",
    "status": summary_status,
    "instance": instance,
    "compose": compose_section,
    "targets": {
        "requested": primary_targets,
        "automatic": auto_targets,
        "all": all_targets,
    },
    "logs": {
        "entries": services_entries,
        "failed": failed_services,
        "has_success": log_success,
        "total": len(services_entries),
        "successful": sum(1 for entry in services_entries if entry.get("status") == "ok"),
    },
}

print(json.dumps(result, ensure_ascii=False, indent=2))
PYTHON
  )"

  if [[ -n "$OUTPUT_FILE" ]]; then
    printf '%s\n' "$json_payload" >"$OUTPUT_FILE"
  fi

  printf '%s\n' "$json_payload"
fi
