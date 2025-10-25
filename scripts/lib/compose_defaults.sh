#!/usr/bin/env bash
set -euo pipefail

# Configure docker compose defaults based on the provided instance name.
# Arguments:
#   $1 - Instance name (optional).
#   $2 - Base directory for compose/env files (defaults to current directory).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

setup_compose_defaults() {
  local instance="${1:-}"
  local base_dir="${2:-.}"
  local base_fs
  local compose_metadata=""

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
    if compose_metadata="$("$SCRIPT_DIR/lib/compose_instances.sh" "$base_fs")"; then
      eval "$compose_metadata"

      if [[ -n "${COMPOSE_INSTANCE_FILES[$instance]:-}" ]]; then
        mapfile -t __instance_compose_files < <(printf '%s
' "${COMPOSE_INSTANCE_FILES[$instance]}")
        local files_list=("$BASE_COMPOSE_FILE")
        local item
        for item in "${__instance_compose_files[@]}"; do
          [[ -z "$item" ]] && continue
          files_list+=("$item")
        done
        COMPOSE_FILES="${files_list[*]}"
      fi
    fi

    if [[ -z "${COMPOSE_FILES:-}" ]]; then
      COMPOSE_FILES="compose/base.yml"
    fi
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

  if [[ -n "${DOCKER_COMPOSE_BIN:-}" ]]; then
    # shellcheck disable=SC2206
    COMPOSE_CMD=(${DOCKER_COMPOSE_BIN})
  else
    COMPOSE_CMD=(docker compose)
  fi

  if [[ -n "${COMPOSE_ENV_FILE:-}" ]]; then
    COMPOSE_CMD+=(--env-file "$COMPOSE_ENV_FILE")
  fi

  local compose_files_entries=()
  local extra_files_entries=()

  if [[ -n "${COMPOSE_FILES:-}" ]]; then
    IFS=$' 	
' read -r -a compose_files_entries <<<"${COMPOSE_FILES}"
  fi

  if [[ -n "${COMPOSE_EXTRA_FILES:-}" ]]; then
    IFS=$' 	
' read -r -a extra_files_entries <<<"${COMPOSE_EXTRA_FILES//,/ }"
  fi

  if [[ ${#extra_files_entries[@]} -gt 0 ]]; then
    compose_files_entries+=("${extra_files_entries[@]}")
  fi

  if [[ ${#compose_files_entries[@]} -gt 0 ]]; then
    COMPOSE_FILES="${compose_files_entries[*]}"
    for file in "${compose_files_entries[@]}"; do
      COMPOSE_CMD+=(-f "$file")
    done
  fi
}

main() {
  local instance="${1:-}"
  local base_dir="${2:-.}"

  setup_compose_defaults "$instance" "$base_dir"

  declare -p COMPOSE_FILES COMPOSE_ENV_FILE COMPOSE_CMD
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
