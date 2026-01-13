#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Maintenance script to check and recover SQLite databases.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ORIGINAL_PWD="${PWD:-}"
CHANGED_TO_REPO_ROOT=false

# shellcheck source=lib/app_detection.sh
source "$SCRIPT_DIR/lib/app_detection.sh"

# shellcheck source=lib/compose_command.sh
source "$SCRIPT_DIR/lib/compose_command.sh"

# shellcheck source=lib/db_integrity_backend.sh
source "$SCRIPT_DIR/lib/db_integrity_backend.sh"

# shellcheck source=lib/db_integrity_recovery.sh
source "$SCRIPT_DIR/lib/db_integrity_recovery.sh"

# shellcheck source=lib/db_integrity_report.sh
source "$SCRIPT_DIR/lib/db_integrity_report.sh"

if [[ "$ORIGINAL_PWD" != "$REPO_ROOT" ]]; then
  cd "$REPO_ROOT"
  CHANGED_TO_REPO_ROOT=true
fi

INSTANCE_NAME=""
REQUESTED_DATA_DIR="" # Used by the routine registered in trap.
RESUME_ON_EXIT=1
SQLITE3_BIN="${SQLITE3_BIN:-sqlite3}"
SQLITE3_MODE="${SQLITE3_MODE:-container}"
SQLITE3_CONTAINER_RUNTIME="${SQLITE3_CONTAINER_RUNTIME:-docker}"
SQLITE3_CONTAINER_IMAGE="${SQLITE3_CONTAINER_IMAGE:-keinos/sqlite3:latest}"
OUTPUT_FORMAT="text"
OUTPUT_FILE=""
JSON_STDOUT_REDIRECTED=0

SQLITE3_BACKEND=""
SQLITE3_BIN_PATH=""

declare -ag COMPOSE_CMD=()
declare -ag PAUSED_SERVICES=() # Updated when services are paused and read in the EXIT trap.
PAUSED_STACK=0

ALERTS=()
FIELD_SEPARATOR=$'\x1f'
declare -a DB_RESULTS=()

print_help() {
  cat <<'USAGE'
Usage: scripts/check_db_integrity.sh instance [options]

Pauses active instance services, checks the integrity of SQLite (*.db) files
inside the data directory (or a custom directory), and attempts recovery
when needed.

Positional arguments:
  instance               Name of the instance defined in docker compose manifests.

Options:
  --data-dir <dir>       Base directory containing .db files (default: data/).
  --format {text,json}   Sets the output format (default: text).
  --no-resume            Do not resume services after verification.
  --output <file>        Path to write the final summary.
  -h, --help             Show this help and exit.

Relevant environment variables:
  SQLITE3_MODE           Forces 'container', 'binary', or 'auto' (default: container).
  SQLITE3_CONTAINER_RUNTIME  Container runtime to use (default: docker).
  SQLITE3_CONTAINER_IMAGE    sqlite3 container image (default: keinos/sqlite3:latest).
  SQLITE3_BIN            Path to a local sqlite3 binary (used in binary mode or fallback).
  DATA_DIR               Alternative to --data-dir.

Examples:
  scripts/check_db_integrity.sh core
  DATA_DIR="/mnt/storage/data" scripts/check_db_integrity.sh media --no-resume
USAGE
}

trap '
  if ((PAUSED_STACK == 1 && RESUME_ON_EXIT == 1)); then
    if [[ ${#COMPOSE_CMD[@]} -gt 0 && ${#PAUSED_SERVICES[@]} -gt 0 ]]; then
      if ! "${COMPOSE_CMD[@]}" unpause "${PAUSED_SERVICES[@]}" >/dev/null 2>&1; then
        echo "[!] Failed to resume services: ${PAUSED_SERVICES[*]}" >&2
      else
        echo "[+] Services resumed: ${PAUSED_SERVICES[*]}" >&2
      fi
    fi
  fi

  if [[ $CHANGED_TO_REPO_ROOT == true ]]; then
    cd "$ORIGINAL_PWD" >/dev/null 2>&1 || true
  fi
' EXIT

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -h | --help)
      print_help
      exit 0
      ;;
    --format)
      shift
      if [[ $# -eq 0 ]]; then
        echo "Error: --format requires an argument (text|json)." >&2
        exit 1
      fi
      case "$1" in
      text | json)
        OUTPUT_FORMAT="$1"
        ;;
      *)
        echo "Error: invalid value for --format: $1" >&2
        exit 1
        ;;
      esac
      ;;
    --format=*)
      case "${1#*=}" in
      text | json)
        OUTPUT_FORMAT="${1#*=}"
        ;;
      *)
        echo "Error: invalid value for --format: ${1#*=}" >&2
        exit 1
        ;;
      esac
      ;;
    --data-dir)
      shift
      if [[ $# -eq 0 ]]; then
        echo "Error: --data-dir requires an argument." >&2
        exit 1
      fi
      REQUESTED_DATA_DIR="$1"
      ;;
    --no-resume)
      # shellcheck disable=SC2034  # Read by the EXIT trap.
      RESUME_ON_EXIT=0
      ;;
    --output)
      shift
      if [[ $# -eq 0 ]]; then
        echo "Error: --output requires a path." >&2
        exit 1
      fi
      OUTPUT_FILE="$1"
      ;;
    --output=*)
      OUTPUT_FILE="${1#*=}"
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Error: unknown option '$1'." >&2
      exit 1
      ;;
    *)
      if [[ -z "$INSTANCE_NAME" ]]; then
        INSTANCE_NAME="$1"
      else
        echo "Error: unexpected argument '$1'." >&2
        exit 1
      fi
      ;;
    esac
    shift || true
  done

  if [[ -z "$INSTANCE_NAME" ]]; then
    echo "Error: provide the instance to analyze." >&2
    print_help >&2
    exit 1
  fi
}

parse_args "$@"

if [[ "$OUTPUT_FORMAT" == "json" ]]; then
  exec 3>&1
  exec 1>&2
  JSON_STDOUT_REDIRECTED=1
fi

DATA_DIR="${REQUESTED_DATA_DIR:-${DATA_DIR:-data}}"
if [[ "$DATA_DIR" != /* ]]; then
  DATA_DIR="$REPO_ROOT/$DATA_DIR"
fi

if [[ ! -d "$DATA_DIR" ]]; then
  echo "Error: data directory not found: $DATA_DIR" >&2
  exit 1
fi

resolve_sqlite_backend

if [[ "$SQLITE3_BACKEND" == "container" ]]; then
  echo "[i] Running sqlite3 via container '$SQLITE3_CONTAINER_IMAGE' (runtime: $SQLITE3_CONTAINER_RUNTIME)." >&2
fi

unset COMPOSE_FILES
unset COMPOSE_EXTRA_FILES

COMPOSE_ROOT_FILE="$REPO_ROOT/docker-compose.yml"
declare -a BUILD_COMPOSE_CMD=("$SCRIPT_DIR/build_compose_file.sh" "$INSTANCE_NAME")

if ! "${BUILD_COMPOSE_CMD[@]}" >/dev/null; then
  echo "[!] Unable to prepare docker-compose.yml for '$INSTANCE_NAME'." >&2
  exit 1
fi

declare -a DOCKER_COMPOSE_CMD=()
compose_resolve_command DOCKER_COMPOSE_CMD
compose_status=$?
if ((compose_status != 0)); then
  exit "$compose_status"
fi

COMPOSE_CMD=("${DOCKER_COMPOSE_CMD[@]}" -f "$COMPOSE_ROOT_FILE")

if ! app_detection__list_active_services PAUSED_SERVICES "${COMPOSE_CMD[@]}"; then
  echo "[!] Unable to list active services for instance '$INSTANCE_NAME'." >&2
  PAUSED_SERVICES=()
fi

if ((${#PAUSED_SERVICES[@]} > 0)); then
  if [[ "$OUTPUT_FORMAT" == "text" ]]; then
    echo "[*] Pausing active services: ${PAUSED_SERVICES[*]}"
  else
    echo "[*] Pausing active services: ${PAUSED_SERVICES[*]}" >&2
  fi
  if ! "${COMPOSE_CMD[@]}" pause "${PAUSED_SERVICES[@]}"; then
    echo "[!] Failed to pause services: ${PAUSED_SERVICES[*]}" >&2
  else
    # shellcheck disable=SC2034  # Read by the EXIT trap.
    PAUSED_STACK=1
  fi
else
  if [[ "$OUTPUT_FORMAT" == "text" ]]; then
    echo "[*] No running services found to pause."
  else
    echo "[*] No running services found to pause." >&2
  fi
fi

declare -a DB_FILES=()
while IFS= read -r -d '' file; do
  DB_FILES+=("$file")
done < <(find "$DATA_DIR" -type f -name '*.db' -print0)

if ((${#DB_FILES[@]} == 0)); then
  if [[ "$OUTPUT_FORMAT" == "text" ]]; then
    echo "[i] No .db files found in $DATA_DIR."
  else
    echo "[i] No .db files found in $DATA_DIR." >&2
  fi
  exit 0
fi

overall_status=0

for db_file in "${DB_FILES[@]}"; do
  if [[ "$OUTPUT_FORMAT" == "text" ]]; then
    echo "[*] Checking integrity of: $db_file"
  else
    echo "[*] Checking integrity of: $db_file" >&2
  fi
  check_output=""
  check_status=0
  if ! check_output="$(sqlite3_exec "$db_file" "PRAGMA integrity_check;" 2>&1)"; then
    check_status=$?
  fi

  if ((check_status != 0)) || [[ "$check_output" != "ok" ]]; then
    local_message="Integrity check failed: ${check_output//$'\n'/; }"
    ALERTS+=("$local_message in $db_file")
    if attempt_recovery "$db_file"; then
      action_message="Automatic recovery completed. Backup saved at $RECOVERY_BACKUP_PATH (${RECOVERY_DETAILS})."
      ALERTS+=("Database '$db_file' recovered. Backup saved at $RECOVERY_BACKUP_PATH (${RECOVERY_DETAILS}).")
      record_result "$db_file" "recovered" "$local_message" "$action_message"
      echo "[!] $local_message" >&2
      if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo "[+] Database recovered, backup at $RECOVERY_BACKUP_PATH"
      else
        echo "[+] Database recovered, backup at $RECOVERY_BACKUP_PATH" >&2
      fi
    else
      action_message="Automatic recovery failed: $RECOVERY_DETAILS"
      ALERTS+=("Database '$db_file' remains corrupted: $RECOVERY_DETAILS")
      record_result "$db_file" "failed" "$local_message" "$action_message"
      echo "[!] $local_message" >&2
      echo "[!] Failed to recover $db_file: $RECOVERY_DETAILS" >&2
      overall_status=2
    fi
  else
    record_result "$db_file" "ok" "Integrity OK" "No action required"
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
      echo "[+] Integrity OK"
    else
      echo "[+] Integrity OK" >&2
    fi
  fi

done

if ((${#ALERTS[@]} > 0)); then
  echo "=== ALERTS GENERATED ===" >&2
  for alert in "${ALERTS[@]}"; do
    echo "- $alert" >&2
  done
fi

if [[ "$OUTPUT_FORMAT" == "json" ]]; then
  json_report="$(generate_json_report)"
  if ((JSON_STDOUT_REDIRECTED == 1)); then
    exec 1>&3
    exec 3>&-
    JSON_STDOUT_REDIRECTED=0
  fi
  if [[ -n "$OUTPUT_FILE" ]]; then
    printf '%s\n' "$json_report" >"$OUTPUT_FILE"
  fi
  printf '%s\n' "$json_report"
else
  if [[ -n "$OUTPUT_FILE" ]]; then
    generate_text_report >"$OUTPUT_FILE"
  fi
fi

exit "$overall_status"
