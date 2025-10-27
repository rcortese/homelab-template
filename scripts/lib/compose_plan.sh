#!/usr/bin/env bash

# Utility functions for assembling docker compose file plans based on repository
# metadata. These helpers operate on the COMPOSE_INSTANCE_* structures produced
# by compose_instances.sh and keep the logic centralized across scripts.

append_unique_file() {
  local -n __target_array=$1
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

# Build the ordered list of compose files for the provided instance.
# Arguments:
#   $1 - Instance name.
#   $2 - Name of the array variable that receives the resulting file list.
#   $3 - (optional) Name of an array variable containing extra compose files
#        that should be appended to the plan.
#   $4 - (optional) Name of an associative array variable that will receive
#        metadata (newline-separated strings) about the generated plan. Keys:
#          app_names        -> apps associated with the instance.
#          discovered_files -> files declared in COMPOSE_INSTANCE_FILES.
#          extra_files      -> any extra files appended to the plan.
build_compose_file_plan() {
  local instance_name="$1"
  local target_array_name="$2"
  local extras_array_name="${3:-}"
  local metadata_assoc_name="${4:-}"

  if [[ -z "$instance_name" || -z "$target_array_name" ]]; then
    return 1
  fi

  if [[ ! -v COMPOSE_INSTANCE_FILES[$instance_name] ]]; then
    return 1
  fi

  if [[ -z "${BASE_COMPOSE_FILE:-}" ]]; then
    return 1
  fi

  local -n __plan_ref=$target_array_name
  __plan_ref=()

  local -a __extras_ref_copy=()
  if [[ -n "$extras_array_name" ]]; then
    local -n __extras_ref=$extras_array_name
    __extras_ref_copy=("${__extras_ref[@]}")
  fi

  local -a __instance_compose_files=()
  mapfile -t __instance_compose_files < <(printf '%s\n' "${COMPOSE_INSTANCE_FILES[$instance_name]}")

  local -a __instance_app_names=()
  if [[ -n "${COMPOSE_INSTANCE_APP_NAMES[$instance_name]:-}" ]]; then
    mapfile -t __instance_app_names < <(printf '%s\n' "${COMPOSE_INSTANCE_APP_NAMES[$instance_name]}")
  fi

  append_unique_file __plan_ref "$BASE_COMPOSE_FILE"

  local -a __instance_level_overrides=()
  declare -A __overrides_by_app=()
  local __compose_file __app_for_file
  for __compose_file in "${__instance_compose_files[@]}"; do
    [[ -z "$__compose_file" ]] && continue
    if [[ "$__compose_file" == "compose/${instance_name}.yml" || "$__compose_file" == "compose/${instance_name}.yaml" ]]; then
      append_unique_file __instance_level_overrides "$__compose_file"
      continue
    fi
    __app_for_file="${__compose_file#compose/apps/}"
    __app_for_file="${__app_for_file%%/*}"
    if [[ -z "$__app_for_file" ]]; then
      continue
    fi
    if [[ -n "${__overrides_by_app[$__app_for_file]:-}" ]]; then
      __overrides_by_app[$__app_for_file]+=$'\n'"$__compose_file"
    else
      __overrides_by_app[$__app_for_file]="$__compose_file"
    fi
  done

  local __instance_override
  for __instance_override in "${__instance_level_overrides[@]}"; do
    append_unique_file __plan_ref "$__instance_override"
  done

  local __app_name
  local __app_base_file
  for __app_name in "${__instance_app_names[@]}"; do
    __app_base_file="${COMPOSE_APP_BASE_FILES[$__app_name]:-}"
    if [[ -n "$__app_base_file" ]]; then
      append_unique_file __plan_ref "$__app_base_file"
    fi
    if [[ -n "${__overrides_by_app[$__app_name]:-}" ]]; then
      mapfile -t __instance_compose_files < <(printf '%s\n' "${__overrides_by_app[$__app_name]}")
      local __override_file
      for __override_file in "${__instance_compose_files[@]}"; do
        append_unique_file __plan_ref "$__override_file"
      done
    fi
  done

  mapfile -t __instance_compose_files < <(printf '%s\n' "${COMPOSE_INSTANCE_FILES[$instance_name]}")
  for __compose_file in "${__instance_compose_files[@]}"; do
    append_unique_file __plan_ref "$__compose_file"
  done

  if [[ ${#__extras_ref_copy[@]} -gt 0 ]]; then
    __plan_ref+=("${__extras_ref_copy[@]}")
  fi

  if [[ -n "$metadata_assoc_name" ]]; then
    declare -gA "$metadata_assoc_name"
    local -n __metadata_ref=$metadata_assoc_name
    __metadata_ref=()

    if [[ ${#__instance_app_names[@]} -gt 0 ]]; then
      __metadata_ref["app_names"]="$(printf '%s\n' "${__instance_app_names[@]}")"
    fi

    if [[ ${#__instance_compose_files[@]} -gt 0 ]]; then
      __metadata_ref["discovered_files"]="$(printf '%s\n' "${__instance_compose_files[@]}")"
    fi

    if [[ ${#__extras_ref_copy[@]} -gt 0 ]]; then
      __metadata_ref["extra_files"]="$(printf '%s\n' "${__extras_ref_copy[@]}")"
    fi
  fi

  return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "This script is intended to be sourced." >&2
  exit 1
fi
