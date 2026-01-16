#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Usage: scripts/validate_compose.sh
#
# Arguments:
#   (none) — the script validates known instances using only the base file plus the instance override.
# Environment:
#   DOCKER_COMPOSE_BIN   Overrides the binary used (for example: docker-compose).
#   COMPOSE_INSTANCES    List of instances to validate (space- or comma-separated). Default: all.
#   COMPOSE_EXTRA_FILES  Extra compose files applied after the default override file (spaces or commas accepted).
# Examples:
#   scripts/validate_compose.sh
#   COMPOSE_INSTANCES="media" scripts/validate_compose.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_LOADER="$SCRIPT_DIR/_internal/lib/env_loader.sh"

# shellcheck source=_internal/lib/compose_paths.sh
source "$SCRIPT_DIR/_internal/lib/compose_paths.sh"

if ! REPO_ROOT="$(compose_common__resolve_repo_root "")"; then
  exit 1
fi

# shellcheck source=_internal/lib/compose_command.sh
source "$SCRIPT_DIR/_internal/lib/compose_command.sh"

# shellcheck source=_internal/lib/compose_file_utils.sh
source "$SCRIPT_DIR/_internal/lib/compose_file_utils.sh"
# shellcheck source=_internal/lib/validate_cli.sh
source "$SCRIPT_DIR/_internal/lib/validate_cli.sh"
# shellcheck source=_internal/lib/validate_executor.sh
source "$SCRIPT_DIR/_internal/lib/validate_executor.sh"

POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    validate_cli_print_help
    exit 0
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

if ! compose_metadata="$("$SCRIPT_DIR/_internal/lib/compose_instances.sh" "$REPO_ROOT" "${COMPOSE_INSTANCES:-}")"; then
  echo "Error: unable to load instance metadata." >&2
  exit 1
fi

eval "$compose_metadata"

if [[ -n "${BASE_COMPOSE_FILE:-}" ]]; then
  base_file="$REPO_ROOT/$BASE_COMPOSE_FILE"
else
  base_file=""
fi
# referenced indirectly via nameref in validate_cli_parse_instances
declare -a instances_to_validate=()
if validate_cli_parse_instances instances_to_validate "$@"; then
  :
else
  cli_status=$?
  if [[ $cli_status -eq 2 ]]; then
    exit 0
  fi
  exit $cli_status
fi

declare -a compose_cmd=()
if compose_resolve_command compose_cmd; then
  :
else
  status=$?
  exit $status
fi

# Touch the array to satisfy static analysis before passing via nameref.
: "${instances_to_validate[@]}"

validate_executor_run_instances "$REPO_ROOT" "$base_file" "$ENV_LOADER" instances_to_validate "${compose_cmd[@]}"
executor_status=$?
if [[ $executor_status -eq 2 ]]; then
  exit 1
elif [[ $executor_status -ne 0 ]]; then
  exit $executor_status
fi

exit 0
