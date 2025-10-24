#!/usr/bin/env bash
set -euo pipefail

# Configure docker compose defaults based on the provided instance name.
# Arguments:
#   $1 - Instance name (optional).
#   $2 - Base directory for compose/env files (defaults to current directory).
setup_compose_defaults() {
  local instance="${1:-}"
  local base_dir="${2:-.}"
  local base_fs

  declare -g COMPOSE_FILES="${COMPOSE_FILES:-}"
  declare -g COMPOSE_ENV_FILE="${COMPOSE_ENV_FILE:-}"
  declare -ga COMPOSE_CMD=()

  if [[ "$base_dir" == "." ]]; then
    base_fs="$(pwd)"
  else
    if ! base_fs="$(cd "$base_dir" 2>/dev/null && pwd)"; then
      base_fs="$base_dir"
    fi
  fi

  if [[ -z "${COMPOSE_FILES:-}" && -n "$instance" ]]; then
    COMPOSE_FILES="compose/base.yml compose/${instance}.yml"
  fi

  if [[ -z "${COMPOSE_ENV_FILE:-}" && -n "$instance" ]]; then
    local env_candidate_rel="env/local/${instance}.env"
    local env_candidate_abs
    if [[ -n "$base_fs" ]]; then
      env_candidate_abs="${base_fs%/}/${env_candidate_rel}"
    else
      env_candidate_abs="$env_candidate_rel"
    fi

    if [[ -f "$env_candidate_abs" ]]; then
      if [[ "$base_dir" == "." ]]; then
        COMPOSE_ENV_FILE="$env_candidate_rel"
      else
        COMPOSE_ENV_FILE="$env_candidate_abs"
      fi
    fi
  fi

  COMPOSE_CMD=(docker compose)

  if [[ -n "${COMPOSE_ENV_FILE:-}" ]]; then
    COMPOSE_CMD+=(--env-file "$COMPOSE_ENV_FILE")
  fi

  if [[ -n "${COMPOSE_FILES:-}" ]]; then
    # shellcheck disable=SC2086
    for file in ${COMPOSE_FILES}; do
      COMPOSE_CMD+=(-f "$file")
    done
  fi
}

main() {
  local instance="${1:-}"
  local base_dir="${2:-.}"

  setup_compose_defaults "$instance" "$base_dir"

  declare -p \
    COMPOSE_FILES \
    COMPOSE_ENV_FILE \
    COMPOSE_CMD
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi

