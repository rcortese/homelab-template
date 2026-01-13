#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

print_help() {
  cat <<'USAGE'
Usage: scripts/describe_instance.sh [--list] <instance> [--format <format>]

Generates a summary of services, ports, and volumes for the requested instance
from `docker compose config`, reusing the template conventions.

Positional arguments:
  instance             Instance name (e.g. core, media).

Flags:
  -h, --help           Show this help and exit.
  --list               List available instances and exit.
  --format <format>    Set output format. Accepted values: table (default), json.
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=lib/python_runtime.sh
source "${SCRIPT_DIR}/lib/python_runtime.sh"

# shellcheck source=lib/compose_command.sh
source "$SCRIPT_DIR/lib/compose_command.sh"

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
      echo "Error: extra arguments not recognized: '$1'." >&2
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

unset COMPOSE_FILES
unset COMPOSE_EXTRA_FILES

COMPOSE_ROOT_FILE="$REPO_ROOT/docker-compose.yml"
declare -a BUILD_COMPOSE_CMD=("$SCRIPT_DIR/build_compose_file.sh" "$INSTANCE_NAME")

if ! "${BUILD_COMPOSE_CMD[@]}" >/dev/null; then
  echo "Error: failed to assemble compose configuration for '$INSTANCE_NAME'." >&2
  exit 1
fi

declare -a COMPOSE_CMD=()
compose_resolve_command COMPOSE_CMD
compose_status=$?
if ((compose_status != 0)); then
  exit "$compose_status"
fi

declare -a CONFIG_CMD=("${COMPOSE_CMD[@]}" -f "$COMPOSE_ROOT_FILE" config --format json)

tmp_stderr="$(mktemp)"
set +e
config_stdout="$("${CONFIG_CMD[@]}" 2>"$tmp_stderr")"
config_status=$?
set -e

if [[ $config_status -ne 0 ]]; then
  echo "Error: failed to run docker compose config." >&2
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
export DESCRIBE_INSTANCE_COMPOSE_FILES="docker-compose.yml"
export DESCRIBE_INSTANCE_EXTRA_FILES=""
export DESCRIBE_INSTANCE_REPO_ROOT="$REPO_ROOT"

printf '%s' "$config_stdout" | python_runtime__run \
  "$REPO_ROOT" \
  "DESCRIBE_INSTANCE_FORMAT DESCRIBE_INSTANCE_NAME DESCRIBE_INSTANCE_COMPOSE_FILES DESCRIBE_INSTANCE_EXTRA_FILES DESCRIBE_INSTANCE_REPO_ROOT" \
  -- "$SCRIPT_DIR/lib/describe_instance_report.py"
