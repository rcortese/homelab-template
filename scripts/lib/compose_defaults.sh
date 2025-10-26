#!/usr/bin/env bash
set -euo pipefail

# Configure docker compose defaults based on the provided instance name.
# Arguments:
#   $1 - Instance name (optional).
#   $2 - Base directory for compose/env files (defaults to current directory).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=./lib/env_file_chain.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/env_file_chain.sh"

append_unique_file() {
  local -n __target_array="$1"
  local __file="$2"
  local existing

  if [[ -z "$__file" ]]; then
    return
  fi

  for existing in "${__target_array[@]}"; do
    if [[ "$existing" == "$__file" ]]; then
      return
    fi
  done

  __target_array+=("$__file")
}

split_compose_entries() {
  local raw="${1:-}"
  local -n __out="$2"

  __out=()

  if [[ -z "$raw" ]]; then
    return
  fi

  local sanitized="${raw//$'\n'/ }"
  sanitized="${sanitized//,/ }"

  local token
  for token in $sanitized; do
    if [[ -z "$token" ]]; then
      continue
    fi
    __out+=("$token")
  done
}

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
  if [[ -n "$instance" ]]; then
    if compose_metadata="$("$SCRIPT_DIR/lib/compose_instances.sh" "$base_fs")"; then
      eval "$compose_metadata"
      metadata_loaded=1
    fi
  fi

  if [[ -z "${COMPOSE_FILES:-}" ]]; then
    if [[ -n "$instance" && $metadata_loaded -eq 1 && -n "${COMPOSE_INSTANCE_FILES[$instance]:-}" ]]; then
      mapfile -t __instance_compose_files < <(printf '%s\n' "${COMPOSE_INSTANCE_FILES[$instance]}")
      local -a files_list=()

      append_unique_file files_list "$BASE_COMPOSE_FILE"

      local -a __instance_app_names=()
      local __apps_raw="${COMPOSE_INSTANCE_APP_NAMES[$instance]:-}"
      if [[ -n "$__apps_raw" ]]; then
        mapfile -t __instance_app_names < <(printf '%s\n' "$__apps_raw")
      fi

      declare -A __instance_overrides_by_app=()
      local __compose_entry __app_for_entry
      for __compose_entry in "${__instance_compose_files[@]}"; do
        [[ -z "$__compose_entry" ]] && continue
        __app_for_entry="${__compose_entry#compose/apps/}"
        __app_for_entry="${__app_for_entry%%/*}"
        if [[ -z "$__app_for_entry" ]]; then
          continue
        fi
        if [[ -n "${__instance_overrides_by_app[$__app_for_entry]:-}" ]]; then
          __instance_overrides_by_app[$__app_for_entry]+=$'\n'"$__compose_entry"
        else
          __instance_overrides_by_app[$__app_for_entry]="$__compose_entry"
        fi
      done

      local __app_name
      for __app_name in "${__instance_app_names[@]}"; do
        append_unique_file files_list "compose/apps/${__app_name}/base.yml"
        if [[ -n "${__instance_overrides_by_app[$__app_name]:-}" ]]; then
          local -a __app_override_entries=()
          mapfile -t __app_override_entries < <(printf '%s\n' "${__instance_overrides_by_app[$__app_name]}")
          local __override_entry
          for __override_entry in "${__app_override_entries[@]}"; do
            append_unique_file files_list "$__override_entry"
          done
        fi
      done

      for __compose_entry in "${__instance_compose_files[@]}"; do
        append_unique_file files_list "$__compose_entry"
      done

      COMPOSE_FILES="${files_list[*]}"
    fi

    if [[ -z "${COMPOSE_FILES:-}" ]]; then
      COMPOSE_FILES="compose/base.yml"
    fi
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
  env_file_chain__resolve_explicit "$explicit_env_input" "$metadata_env_input" env_files_rel

  if (( ${#env_files_rel[@]} == 0 )) && [[ -n "$instance" ]]; then
    env_file_chain__defaults "$base_fs" "$instance" env_files_rel
  fi

  declare -a env_files_abs=()
  env_file_chain__to_absolute "$base_fs" env_files_rel env_files_abs

  if (( ${#env_files_abs[@]} > 0 )); then
    COMPOSE_ENV_FILE="${env_files_abs[-1]}"
    COMPOSE_ENV_FILES="$(printf '%s\n' "${env_files_abs[@]}")"
    COMPOSE_ENV_FILES="${COMPOSE_ENV_FILES%$'\n'}"
  else
    COMPOSE_ENV_FILE=""
    COMPOSE_ENV_FILES=""
  fi

  if [[ -z "${DOCKER_COMPOSE_BIN:-}" ]]; then
    COMPOSE_CMD=(docker compose)
  else
    # shellcheck disable=SC2206
    COMPOSE_CMD=(${DOCKER_COMPOSE_BIN})
  fi

  if (( ${#env_files_abs[@]} > 0 )); then
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
      if env_loader_output="$("$SCRIPT_DIR/lib/env_loader.sh" "$env_file_path" COMPOSE_EXTRA_FILES 2>/dev/null)"; then
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

  split_compose_entries "${COMPOSE_FILES:-}" compose_files_entries

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
    split_compose_entries "$resolved_extra_files" extra_files_entries
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

  if [[ ${#extra_files_entries[@]} > 0 ]]; then
    local -a combined_entries=("${compose_files_entries[@]}" "${extra_files_entries[@]}")
    COMPOSE_FILES="${combined_entries[*]}"
  else
    COMPOSE_FILES="${compose_files_entries[*]}"
  fi

  local -a final_compose_entries=()
  split_compose_entries "${COMPOSE_FILES:-}" final_compose_entries

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
