#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR/lib
# Usage: scripts/validate_compose.sh
#
# Arguments:
#   (nenhum) — o script valida as instâncias conhecidas usando somente base + override da instância.
# Environment:
#   DOCKER_COMPOSE_BIN  Sobrescreve o binário usado (ex.: docker-compose).
#   COMPOSE_INSTANCES   Lista de instâncias a validar (separadas por espaço ou vírgula). Default: todas.
# Examples:
#   scripts/validate_compose.sh
#   COMPOSE_INSTANCES="media" scripts/validate_compose.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_LOADER="$SCRIPT_DIR/lib/env_loader.sh"

# shellcheck source=lib/compose_file_utils.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/compose_file_utils.sh"
# shellcheck source=lib/validate_cli.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/validate_cli.sh"
# shellcheck source=lib/validate_executor.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/validate_executor.sh"

if ! compose_metadata="$("$SCRIPT_DIR/lib/compose_instances.sh" "$REPO_ROOT")"; then
  echo "Error: não foi possível carregar metadados das instâncias." >&2
  exit 1
fi

eval "$compose_metadata"

base_file="$REPO_ROOT/$BASE_COMPOSE_FILE"

# shellcheck disable=SC2034 # referenced indirectly via nameref in validate_cli_parse_instances
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

if [[ -n "${DOCKER_COMPOSE_BIN:-}" ]]; then
  # Allow overriding the docker compose binary (e.g., "docker-compose").
  # shellcheck disable=SC2206
  compose_cmd=(${DOCKER_COMPOSE_BIN})
else
  compose_cmd=(docker compose)
fi

if ! command -v "${compose_cmd[0]}" >/dev/null 2>&1; then
  echo "Error: ${compose_cmd[0]} is not available. Set DOCKER_COMPOSE_BIN if needed." >&2
  exit 127
fi

validate_executor_run_instances "$REPO_ROOT" "$base_file" "$ENV_LOADER" instances_to_validate "${compose_cmd[@]}"
executor_status=$?
if [[ $executor_status -eq 2 ]]; then
  exit 1
elif [[ $executor_status -ne 0 ]]; then
  exit $executor_status
fi

exit 0
