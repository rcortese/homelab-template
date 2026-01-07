#!/usr/bin/env bash
set -euo pipefail

# Configure docker compose defaults based on the provided instance name.
# Arguments:
#   $1 - Instance name (optional).
#   $2 - Base directory for compose/env files (defaults to current directory).

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib/compose_command.sh
source "${LIB_DIR}/compose_command.sh"

# shellcheck source=scripts/lib/compose_plan.sh
source "${LIB_DIR}/compose_plan.sh"

# shellcheck source=scripts/lib/env_file_chain.sh
source "${LIB_DIR}/env_file_chain.sh"

setup_compose_defaults() {
  local instance="${1:-}"
  local base_dir="${2:-.}"
  local base_fs

  declare -g COMPOSE_FILES="${COMPOSE_FILES:-}"
  declare -g COMPOSE_ENV_FILES="${COMPOSE_ENV_FILES:-}"
  declare -ga COMPOSE_CMD=()

  if [[ "$base_dir" == "." ]]; then
    base_fs="$(pwd)"
  else
    if ! base_fs="$(cd "$base_dir" 2>/dev/null && pwd)"; then
      base_fs="$base_dir"
    fi
  fi

  local metadata_loaded=0
  local compose_metadata=""
  if [[ -z "${COMPOSE_FILES:-}" && -n "$instance" ]]; then
    if compose_metadata="$("${LIB_DIR}/compose_instances.sh" "$base_fs")"; then
      eval "$compose_metadata"
      metadata_loaded=1
    fi

    if [[ -z "${COMPOSE_FILES:-}" ]] && ((metadata_loaded == 1)) && [[ -v COMPOSE_INSTANCE_FILES[$instance] ]]; then
      local -a files_list=()
      if build_compose_file_plan "$instance" files_list; then
        COMPOSE_FILES="${files_list[*]}"
      fi
    fi
  fi

  if [[ -z "${COMPOSE_FILES:-}" ]]; then
    local default_base="compose/docker-compose.base.yml"
    if [[ -f "${base_fs%/}/$default_base" ]]; then
      COMPOSE_FILES="$default_base"
    else
      COMPOSE_FILES="$default_base"
    fi
  fi

  local env_chain_input="${COMPOSE_ENV_FILES:-}"
  if [[ -z "$env_chain_input" && -n "$instance" && $metadata_loaded -eq 1 && -n "${COMPOSE_INSTANCE_ENV_FILES[$instance]:-}" ]]; then
    env_chain_input="${COMPOSE_INSTANCE_ENV_FILES[$instance]}"
  fi

  declare -a env_files_rel=()
  mapfile -t env_files_rel < <(
    env_file_chain__resolve_explicit "$env_chain_input" "$base_fs" "$instance"
  )

  declare -a env_files_abs=()
  if ((${#env_files_rel[@]} > 0)); then
    mapfile -t env_files_abs < <(
      env_file_chain__to_absolute "$base_fs" "${env_files_rel[@]}"
    )
  fi

  if ((${#env_files_abs[@]} > 0)); then
    COMPOSE_ENV_FILES="$(printf '%s\n' "${env_files_abs[@]}")"
    COMPOSE_ENV_FILES="${COMPOSE_ENV_FILES%$'\n'}"
  else
    COMPOSE_ENV_FILES=""
  fi

  local -a compose_cmd_resolved=()
  if compose_resolve_command compose_cmd_resolved; then
    COMPOSE_CMD=("${compose_cmd_resolved[@]}")
  else
    return $?
  fi

  if ((${#env_files_abs[@]} > 0)); then
    local env_file_path
    for env_file_path in "${env_files_abs[@]}"; do
      COMPOSE_CMD+=(--env-file "$env_file_path")
    done
  fi

  local -a compose_files_entries=()

  mapfile -t compose_files_entries < <(
    env_file_chain__parse_list "${COMPOSE_FILES:-}"
  )

  if [[ ${#compose_files_entries[@]} -gt 0 ]]; then
    declare -A __base_seen=()
    local -a __deduped_base_entries=()
    local __file
    for __file in "${compose_files_entries[@]}"; do
      if [[ -n "${__base_seen[$__file]:-}" ]]; then
        continue
      fi
      __base_seen["$__file"]=1
      __deduped_base_entries+=("$__file")
    done

    compose_files_entries=("${__deduped_base_entries[@]}")
    unset __deduped_base_entries
    unset __base_seen
  fi

  COMPOSE_FILES="${compose_files_entries[*]}"

  local -a final_compose_entries=()
  mapfile -t final_compose_entries < <(
    env_file_chain__parse_list "${COMPOSE_FILES:-}"
  )

  for file in "${final_compose_entries[@]}"; do
    local resolved="$file"
    if [[ "$resolved" != /* ]]; then
      if [[ -n "$base_fs" ]]; then
        resolved="${base_fs%/}/$resolved"
      fi
    fi
    COMPOSE_CMD+=(-f "$resolved")
  done
}

main() {
  local instance="${1:-}"
  local base_dir="${2:-.}"

  setup_compose_defaults "$instance" "$base_dir"

  declare -p COMPOSE_FILES COMPOSE_ENV_FILES COMPOSE_CMD
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
