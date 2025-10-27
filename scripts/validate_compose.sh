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

# shellcheck source=scripts/lib/compose_command.sh
source "$SCRIPT_DIR/lib/compose_command.sh"

# shellcheck source=scripts/lib/compose_file_utils.sh
source "$SCRIPT_DIR/lib/compose_file_utils.sh"
# shellcheck source=scripts/lib/validate_cli.sh
source "$SCRIPT_DIR/lib/validate_cli.sh"
# shellcheck source=scripts/lib/validate_executor.sh
source "$SCRIPT_DIR/lib/validate_executor.sh"

if ! compose_metadata="$("$SCRIPT_DIR/lib/compose_instances.sh" "$REPO_ROOT")"; then
  echo "Error: não foi possível carregar metadados das instâncias." >&2
  exit 1
fi

eval "$compose_metadata"

base_file="$REPO_ROOT/$BASE_COMPOSE_FILE"
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
