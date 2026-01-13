#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Usage: scripts/check_health.sh [--format text|json] [--output <file>] [instance]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ORIGINAL_PWD="${PWD:-}"
# shellcheck source=./lib/python_runtime.sh
source "${SCRIPT_DIR}/lib/python_runtime.sh"

OUTPUT_FORMAT="text"
OUTPUT_FILE=""

if [[ "$ORIGINAL_PWD" != "$REPO_ROOT" ]]; then
  cd "$REPO_ROOT"
fi

REPO_ROOT="$(pwd)"

# shellcheck source=./lib/compose_command.sh
source "$SCRIPT_DIR/lib/compose_command.sh"

# shellcheck source=./lib/env_helpers.sh
source "$SCRIPT_DIR/lib/env_helpers.sh"

# shellcheck source=./lib/env_file_chain.sh
source "$SCRIPT_DIR/lib/env_file_chain.sh"

# shellcheck source=./lib/health_logs.sh
source "$SCRIPT_DIR/lib/health_logs.sh"

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
  declare -a BUILD_COMPOSE_CMD=("$SCRIPT_DIR/build_compose_file.sh" "$INSTANCE_NAME")

  if ! "${BUILD_COMPOSE_CMD[@]}" >/dev/null; then
    echo "Error: failed to generate consolidated docker-compose.yml." >&2
    exit 1
  fi
else
  if [[ ! -f "$COMPOSE_ROOT_FILE" ]]; then
    echo "Error: docker-compose.yml not found; run scripts/build_compose_file.sh <instance>." >&2
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

primary_targets=()
auto_targets=()
ALL_LOG_TARGETS=()

if ! health_logs__select_targets; then
  exit 1
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

health_logs__collect_logs "${LOG_TARGETS[@]}"

if [[ ${#auto_targets[@]} -gt 0 ]]; then
  health_logs__collect_logs "${auto_targets[@]}"
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
    python_runtime__run \
      "$REPO_ROOT" \
      "COMPOSE_PS_TEXT COMPOSE_PS_JSON PRIMARY_LOG_SERVICES AUTO_LOG_SERVICES ALL_LOG_SERVICES FAILED_SERVICES_STR LOG_SUCCESS_FLAG SERVICE_PAYLOAD INSTANCE_NAME" \
      -- "$SCRIPT_DIR/lib/health_report.py"
  )"

  if [[ -n "$OUTPUT_FILE" ]]; then
    printf '%s\n' "$json_payload" >"$OUTPUT_FILE"
  fi

  printf '%s\n' "$json_payload"
fi
