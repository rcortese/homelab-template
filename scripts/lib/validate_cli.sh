#!/usr/bin/env bash

# shellcheck source=SCRIPTDIR/compose_file_utils.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/compose_file_utils.sh"

# CLI helpers for the validate_compose script.

validate_cli_print_help() {
  cat <<'HELP'
Usage: scripts/validate_compose.sh

Validates the repository instances, ensuring `docker compose config` succeeds
for every combination of base files plus instance overrides.

Positional arguments:
  (none)

Options:
  --legacy-plan      Uses the dynamic combination of -f (legacy mode). Will be removed in a future release.

Relevant environment variables:
  DOCKER_COMPOSE_BIN  Override the docker compose command (for example: docker-compose).
  COMPOSE_INSTANCES   Instances to validate (space- or comma-separated). Default: all.
  COMPOSE_EXTRA_FILES Extra compose files applied after the default override (spaces or commas).

Examples:
  scripts/validate_compose.sh
  COMPOSE_INSTANCES="media" scripts/validate_compose.sh
  COMPOSE_EXTRA_FILES="compose/extra/metrics.yml" scripts/validate_compose.sh
  COMPOSE_INSTANCES="media" \
    COMPOSE_EXTRA_FILES="compose/extra/logging.yml compose/extra/metrics.yml" \
    scripts/validate_compose.sh
HELP
}

validate_cli_parse_instances() {
  local -n __out=$1
  shift

  local first_arg="${1:-}"

  if [[ -n "$first_arg" ]]; then
    case "$first_arg" in
    -h | --help)
      validate_cli_print_help
      return 2
      ;;
    *)
      echo "Unrecognized argument: $first_arg" >&2
      return 1
      ;;
    esac
  fi

  local -a instances=()

  if [[ -n "${COMPOSE_INSTANCES:-}" ]]; then
    IFS=',' read -ra raw_instances <<<"$COMPOSE_INSTANCES"
    local entry token
    for entry in "${raw_instances[@]}"; do
      entry="$(trim "$entry")"
      [[ -z "$entry" ]] && continue
      for token in $entry; do
        token="$(trim "$token")"
        [[ -z "$token" ]] && continue
        instances+=("$token")
      done
    done
  else
    instances=("${COMPOSE_INSTANCE_NAMES[@]}")
  fi

  if [[ ${#instances[@]} -eq 0 ]]; then
    echo "Error: no instance provided for validation." >&2
    return 1
  fi

  __out=("${instances[@]}")
  return 0
}
