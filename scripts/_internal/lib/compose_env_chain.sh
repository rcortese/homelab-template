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

compose_env_chain__load_env_files() {
  local script_dir="$1"
  local output_env_var="$2"
  shift 2

  local -a env_files=("$@")
  local -n env_loaded_ref="$output_env_var"

  env_loaded_ref=()

  if ((${#env_files[@]} == 0)); then
    return 0
  fi

  local env_file env_output line key value
  for env_file in "${env_files[@]}"; do
    if [[ -f "$env_file" ]]; then
      if env_output="$("$script_dir/_internal/lib/env_loader.sh" "$env_file" REPO_ROOT LOCAL_INSTANCE APP_DATA_DIR APP_DATA_DIR_MOUNT 2>/dev/null)"; then
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
