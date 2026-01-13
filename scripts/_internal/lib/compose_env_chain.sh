#!/usr/bin/env bash
# shellcheck shell=bash

# Resolve env-file chains and load env file contents for compose helpers.

compose_env_chain__resolve() {
  local repo_root="$1"
  local instance="$2"
  local explicit_env_raw="${3:-}"
  local output_list_var="$4"
  local output_resolved_var="$5"
  shift 5

  local -a extra_env_files=("$@")
  local explicit_env_input="$explicit_env_raw"

  if ((${#extra_env_files[@]} > 0)); then
    local cli_env_join
    cli_env_join="$(env_file_chain__join ' ' "${extra_env_files[@]}")"
    if [[ -n "$explicit_env_input" ]]; then
      explicit_env_input+=" $cli_env_join"
    else
      explicit_env_input="$cli_env_join"
    fi
  fi

  local env_chain_output=""
  if ! env_chain_output="$(env_file_chain__resolve_explicit "$explicit_env_input" "$repo_root" "$instance")"; then
    return 1
  fi

  local -a resolved_list=()
  local -a resolved_paths=()
  if [[ -n "$env_chain_output" ]]; then
    mapfile -t resolved_list <<<"$env_chain_output"
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
}

compose_env_chain__load_env_files() {
  local script_dir="$1"
  local output_env_var="$2"
  shift 2

  local -a env_files=("$@")
  local -n env_loaded="$output_env_var"

  env_loaded=()

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
            env_loaded[$key]="$value"
          fi
        done <<<"$env_output"
      fi
    fi
  done
}
