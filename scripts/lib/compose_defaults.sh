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
  declare -g COMPOSE_ENV_FILE="${COMPOSE_ENV_FILE:-}"
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
    COMPOSE_FILES="compose/base.yml"
  fi

  local explicit_env_input="${COMPOSE_ENV_FILES:-}"
  if [[ -z "$explicit_env_input" && -n "${COMPOSE_ENV_FILE:-}" ]]; then
    explicit_env_input="$COMPOSE_ENV_FILE"
  fi

  local metadata_env_input=""
  if [[ -n "$instance" && $metadata_loaded -eq 1 && -n "${COMPOSE_INSTANCE_ENV_FILES[$instance]:-}" ]]; then
    metadata_env_input="${COMPOSE_INSTANCE_ENV_FILES[$instance]}"
  fi

  declare -a env_files_rel=()
  if [[ -n "$explicit_env_input" || -n "$metadata_env_input" ]]; then
    mapfile -t env_files_rel < <(
      env_file_chain__resolve_explicit "$explicit_env_input" "$metadata_env_input"
    )
  fi

  if ((${#env_files_rel[@]} == 0)) && [[ -n "$instance" ]]; then
    mapfile -t env_files_rel < <(
      env_file_chain__defaults "$base_fs" "$instance"
    )
  fi

  declare -a env_files_abs=()
  if ((${#env_files_rel[@]} > 0)); then
    mapfile -t env_files_abs < <(
      env_file_chain__to_absolute "$base_fs" "${env_files_rel[@]}"
    )
  fi

  if ((${#env_files_abs[@]} > 0)); then
    COMPOSE_ENV_FILE="${env_files_abs[-1]}"
    COMPOSE_ENV_FILES="$(printf '%s\n' "${env_files_abs[@]}")"
    COMPOSE_ENV_FILES="${COMPOSE_ENV_FILES%$'\n'}"
  else
    COMPOSE_ENV_FILE=""
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

  if [[ -z "${COMPOSE_EXTRA_FILES:-}" && ${#env_files_abs[@]} -gt 0 ]]; then
    local env_loader_output=""
    local env_file_path
    for env_file_path in "${env_files_abs[@]}"; do
      if [[ ! -f "$env_file_path" ]]; then
        continue
      fi
      if env_loader_output="$("${LIB_DIR}/env_loader.sh" "$env_file_path" COMPOSE_EXTRA_FILES 2>/dev/null)"; then
        while IFS='=' read -r key value; do
          [[ -z "$key" ]] && continue
          if [[ "$key" == "COMPOSE_EXTRA_FILES" && -n "$value" ]]; then
            COMPOSE_EXTRA_FILES="$value"
          fi
        done <<<"$env_loader_output"
      fi
    done
  fi

  local -a compose_files_entries=()
  local -a extra_files_entries=()
  local resolved_extra_files="${COMPOSE_EXTRA_FILES:-}"

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

  if [[ -n "$resolved_extra_files" ]]; then
    mapfile -t extra_files_entries < <(
      env_file_chain__parse_list "$resolved_extra_files"
    )
  fi

  if [[ ${#extra_files_entries[@]} -gt 0 ]]; then
    declare -A __extra_seen=()
    local -a __unique_extra_entries=()
    local __extra_file
    for __extra_file in "${extra_files_entries[@]}"; do
      if [[ -n "${__extra_seen[$__extra_file]:-}" ]]; then
        continue
      fi
      __extra_seen["$__extra_file"]=1
      __unique_extra_entries+=("$__extra_file")
    done

    extra_files_entries=("${__unique_extra_entries[@]}")
    unset __unique_extra_entries
    unset __extra_seen
  fi

  if [[ ${#extra_files_entries[@]} -gt 0 && ${#compose_files_entries[@]} -gt 0 ]]; then
    declare -A __base_seen_with_extras=()
    local __base_file
    for __base_file in "${compose_files_entries[@]}"; do
      __base_seen_with_extras["$__base_file"]=1
    done

    local -a __filtered_extra_entries=()
    local __extra_entry
    for __extra_entry in "${extra_files_entries[@]}"; do
      if [[ -n "${__base_seen_with_extras[$__extra_entry]:-}" ]]; then
        continue
      fi
      __filtered_extra_entries+=("$__extra_entry")
    done

    extra_files_entries=("${__filtered_extra_entries[@]}")
    unset __filtered_extra_entries
    unset __base_seen_with_extras
  fi

  if [[ ${#extra_files_entries[@]} -gt 0 ]]; then
    local -a combined_entries=("${compose_files_entries[@]}" "${extra_files_entries[@]}")
    COMPOSE_FILES="${combined_entries[*]}"
  else
    COMPOSE_FILES="${compose_files_entries[*]}"
  fi

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

  declare -p COMPOSE_FILES COMPOSE_ENV_FILES COMPOSE_ENV_FILE COMPOSE_CMD
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
