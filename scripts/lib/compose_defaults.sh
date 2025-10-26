#!/usr/bin/env bash
set -euo pipefail

# Configure docker compose defaults based on the provided instance name.
# Arguments:
#   $1 - Instance name (optional).
#   $2 - Base directory for compose/env files (defaults to current directory).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

  local env_file_abs=""

  if [[ -n "${COMPOSE_ENV_FILE:-}" ]]; then
    if [[ "${COMPOSE_ENV_FILE}" == /* ]]; then
      env_file_abs="${COMPOSE_ENV_FILE}"
    elif [[ -n "$base_fs" ]]; then
      env_file_abs="${base_fs%/}/${COMPOSE_ENV_FILE}"
    else
      env_file_abs="${COMPOSE_ENV_FILE}"
    fi

    if [[ -z "${COMPOSE_EXTRA_FILES:-}" && -f "$env_file_abs" ]]; then
      local env_loader_output=""
      if env_loader_output="$("$SCRIPT_DIR/lib/env_loader.sh" "$env_file_abs" COMPOSE_EXTRA_FILES 2>/dev/null)"; then
        while IFS='=' read -r key value; do
          [[ -z "$key" ]] && continue
          if [[ "$key" == "COMPOSE_EXTRA_FILES" && -n "$value" ]]; then
            COMPOSE_EXTRA_FILES="$value"
          fi
        done <<<"$env_loader_output"
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

  if [[ ${#extra_files_entries[@]} -gt 0 ]]; then
    local -a combined_entries=("${compose_files_entries[@]}" "${extra_files_entries[@]}")
    COMPOSE_FILES="${combined_entries[*]}"
  else
    COMPOSE_FILES="${compose_files_entries[*]}"
  fi

  local -a final_compose_entries=()
  split_compose_entries "${COMPOSE_FILES:-}" final_compose_entries

  for file in "${final_compose_entries[@]}"; do
    COMPOSE_CMD+=(-f "$file")
  done
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
