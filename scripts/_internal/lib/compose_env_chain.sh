#!/usr/bin/env bash
# shellcheck shell=bash

# Resolve env-file chains and load env file contents for compose helpers.

compose_env_chain__resolve() {
  local repo_root="$1"
  local instance="$2"
  local explicit_chain_raw="${3:-}"
  local output_list_var="$4"
  local output_resolved_var="$5"
  local extra_chain_raw="${6:-}"
  shift 6

  local -a extra_env_files=("$@")

  local explicit_chain_requested=0
  local -a explicit_chain=()
  if [[ -n "$explicit_chain_raw" ]]; then
    explicit_chain_requested=1
    mapfile -t explicit_chain < <(env_file_chain__parse_list "$explicit_chain_raw")
    if ((${#explicit_chain[@]} == 0)); then
      echo "Error: explicit env chain requested but no env files were provided." >&2
      return 1
    fi
  fi

  local -a extra_chain=()
  if [[ -n "$extra_chain_raw" ]]; then
    mapfile -t extra_chain < <(env_file_chain__parse_list "$extra_chain_raw")
  fi
  if ((${#extra_env_files[@]} > 0)); then
    extra_chain+=("${extra_env_files[@]}")
  fi

  local -a base_chain=()
  if ((explicit_chain_requested == 1)); then
    base_chain=("${explicit_chain[@]}")
  else
    local defaults_output=""
    if ! defaults_output="$(env_file_chain__defaults "$repo_root" "$instance")"; then
      return 1
    fi
    if [[ -n "$defaults_output" ]]; then
      mapfile -t base_chain <<<"$defaults_output"
    fi
  fi

  local -a resolved_list=()
  local -a resolved_paths=()
  if ((${#base_chain[@]} > 0 || ${#extra_chain[@]} > 0)); then
    mapfile -t resolved_list < <(
      env_file_chain__dedupe_preserve_order "${base_chain[@]}" "${extra_chain[@]}"
    )
  fi

  if ((${#resolved_list[@]} > 0)); then
    mapfile -t resolved_paths < <(
      env_file_chain__to_absolute "$repo_root" "${resolved_list[@]}"
    )
  fi

  local -n output_list="$output_list_var"
  local -n output_resolved="$output_resolved_var"
  output_list=("${resolved_list[@]}")
  output_resolved=("${resolved_paths[@]}")
  : "${output_list[@]}" "${output_resolved[@]}"
}

compose_env_chain__load_env_values() {
  local script_dir="$1"
  local output_env_name="$2"
  local requested_keys_var="$3"
  shift 3

  local -a env_files=("$@")
  local -n env_loaded_ref="$output_env_name"
  local -n requested_keys_ref="$requested_keys_var"

  env_loaded_ref=()

  if ((${#env_files[@]} == 0)); then
    return 0
  fi

  local env_loader_path="$script_dir/_internal/lib/env_loader.sh"
  if [[ ! -f "$env_loader_path" ]]; then
    env_loader_path="$script_dir/env_loader.sh"
  fi

  local env_file env_output line key value
  for env_file in "${env_files[@]}"; do
    if [[ -f "$env_file" ]]; then
      if env_output="$("$env_loader_path" "$env_file" "${requested_keys_ref[@]}" 2>/dev/null)"; then
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          if [[ "$line" == *=* ]]; then
            key="${line%%=*}"
            value="${line#*=}"
            env_loaded_ref["$key"]="$value"
          fi
        done <<<"$env_output"
      fi
    fi
  done
  : "${!env_loaded_ref[@]}"
}

compose_env_chain__enforce_disallowed_vars() {
  local output_env_name="$1"
  local repo_root_message="$2"
  local local_instance_message="$3"
  local app_data_message="$4"

  # shellcheck disable=SC2178
  local -n env_loaded_ref="$output_env_name"

  if [[ -n "${env_loaded_ref[REPO_ROOT]:-}" ]]; then
    echo "$repo_root_message" >&2
    return 1
  fi

  if [[ -n "${env_loaded_ref[LOCAL_INSTANCE]:-}" ]]; then
    echo "$local_instance_message" >&2
    return 1
  fi

  if [[ -n "${env_loaded_ref[APP_DATA_DIR]:-}" || -n "${env_loaded_ref[APP_DATA_DIR_MOUNT]:-}" ]]; then
    echo "$app_data_message" >&2
    return 1
  fi

  return 0
}

compose_env_chain__prepare() {
  local script_dir="$1"
  local repo_root="$2"
  local instance="$3"
  local explicit_chain_raw="${4:-}"
  local output_list_var="$5"
  local output_resolved_var="$6"
  local output_env_var="$7"
  local requested_keys_var="$8"
  local repo_root_message="$9"
  local local_instance_message="${10}"
  local app_data_message="${11}"
  local extra_chain_raw="${12:-}"
  shift 12

  if ! compose_env_chain__resolve \
    "$repo_root" \
    "$instance" \
    "$explicit_chain_raw" \
    "$output_list_var" \
    "$output_resolved_var" \
    "$extra_chain_raw" \
    "$@"; then
    return 1
  fi

  local -n resolved_paths_ref="$output_resolved_var"

  if ! compose_env_chain__load_env_values \
    "$script_dir" \
    "$output_env_var" \
    "$requested_keys_var" \
    "${resolved_paths_ref[@]}"; then
    return 1
  fi

  compose_env_chain__enforce_disallowed_vars \
    "$output_env_var" \
    "$repo_root_message" \
    "$local_instance_message" \
    "$app_data_message"
}
