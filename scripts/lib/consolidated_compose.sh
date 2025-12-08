#!/usr/bin/env bash

# Helpers for working with consolidated docker-compose.yml files.

compose_strip_file_flags() {
  if [[ $# -lt 2 ]]; then
    echo "compose_strip_file_flags: expected source and destination namerefs" >&2
    return 64
  fi

  local -n __source=$1
  local -n __dest=$2

  local -a __source_copy=("${__source[@]}")

  __dest=()
  local idx=0
  while ((idx < ${#__source_copy[@]})); do
    local token="${__source_copy[$idx]}"
    if [[ "$token" == "-f" ]] && ((idx + 1 < ${#__source_copy[@]})); then
      idx=$((idx + 2))
      continue
    fi
    __dest+=("$token")
    idx=$((idx + 1))
  done
}

compose_generate_consolidated() {
  if [[ $# -lt 3 ]]; then
    echo "compose_generate_consolidated: expected <repo_root> <compose_cmd_ref> <output_file> [env_assoc_ref]" >&2
    return 64
  fi

  local repo_root="$1"
  local compose_cmd_name="$2"
  local output_file="$3"
  local env_assoc_name="${4:-}"

  if [[ -z "$repo_root" || -z "$compose_cmd_name" || -z "$output_file" ]]; then
    echo "compose_generate_consolidated: missing required arguments" >&2
    return 64
  fi

  local -n __compose_cmd_ref=$compose_cmd_name
  if ((${#__compose_cmd_ref[@]} == 0)); then
    echo "compose_generate_consolidated: compose command is empty" >&2
    return 1
  fi

  if [[ "$output_file" != /* ]]; then
    output_file="$repo_root/${output_file#./}"
  fi

  local app_data_dir_value=""
  local app_data_dir_mount_value=""
  if [[ -n "$env_assoc_name" ]]; then
    local -n __env_assoc_ref=$env_assoc_name
    app_data_dir_value="${__env_assoc_ref[APP_DATA_DIR]:-}"
    app_data_dir_mount_value="${__env_assoc_ref[APP_DATA_DIR_MOUNT]:-}"
  fi

  local output_dir
  output_dir="$(dirname "$output_file")"
  if [[ -n "$output_dir" && ! -d "$output_dir" ]]; then
    if ! mkdir -p "$output_dir"; then
      echo "compose_generate_consolidated: unable to create output directory: $output_dir" >&2
      return 1
    fi
  fi

  local compose_status=0

  APP_DATA_DIR="$app_data_dir_value" \
    APP_DATA_DIR_MOUNT="$app_data_dir_mount_value" \
    "${__compose_cmd_ref[@]}" config >"$output_file" || compose_status=$?

  if ((compose_status != 0)); then
    rm -f "$output_file"
    return $compose_status
  fi

  return 0
}

compose_prepare_consolidated() {
  if [[ $# -lt 3 ]]; then
    echo "compose_prepare_consolidated: expected <repo_root> <compose_cmd_ref> <output_var> [env_assoc_ref]" >&2
    return 64
  fi

  local repo_root="$1"
  local compose_cmd_name="$2"
  local output_var_name="$3"
  local env_assoc_name="${4:-}"

  local -n __output_ref=$output_var_name
  if [[ -z "$__output_ref" ]]; then
    __output_ref="$repo_root/docker-compose.yml"
  fi

  if ! compose_generate_consolidated "$repo_root" "$compose_cmd_name" "$__output_ref" "$env_assoc_name"; then
    return 1
  fi

  local -n __compose_cmd_ref=$compose_cmd_name
  local -a __normalized=()
  compose_strip_file_flags __compose_cmd_ref __normalized
  __normalized+=(-f "$__output_ref")
  __compose_cmd_ref=("${__normalized[@]}")

  return 0
}
