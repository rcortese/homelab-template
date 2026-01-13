#!/usr/bin/env bash

# Helpers for working with consolidated docker-compose.yml files.

compose_extract_file_plan() {
  if [[ $# -lt 2 ]]; then
    echo "compose_extract_file_plan: expected <compose_cmd_ref> <output_ref>" >&2
    return 64
  fi

  local -n __compose_cmd_ref=$1
  local -n __output_ref=$2

  __output_ref=()
  local idx=0
  while ((idx < ${#__compose_cmd_ref[@]})); do
    local token="${__compose_cmd_ref[$idx]}"
    if [[ "$token" == "-f" || "$token" == "--file" ]] && ((idx + 1 < ${#__compose_cmd_ref[@]})); then
      idx=$((idx + 1))
      __output_ref+=("${__compose_cmd_ref[$idx]}")
    fi
    idx=$((idx + 1))
  done
}

compose_print_root_cause() {
  if [[ $# -lt 2 ]]; then
    echo "compose_print_root_cause: expected <compose_output> <compose_cmd_ref>" >&2
    return 64
  fi

  local compose_output="$1"
  local compose_cmd_name="$2"
  local -n __compose_cmd_ref=$compose_cmd_name

  local root_cause=""
  local compose_line
  while IFS= read -r compose_line; do
    [[ -z "$compose_line" ]] && continue
    root_cause="$compose_line"
    break
  done <<<"$compose_output"

  if [[ -n "$root_cause" ]]; then
    echo "   Root cause (from docker compose): $root_cause" >&2
  fi

  local -a plan_files=()
  compose_extract_file_plan __compose_cmd_ref plan_files
  if ((${#plan_files[@]} > 0)); then
    echo "   compose plan order:" >&2
    local idx
    for idx in "${!plan_files[@]}"; do
      echo "     $((idx + 1)). ${plan_files[$idx]}" >&2
    done
  fi
}

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

  local local_instance=""
  local repo_root_env=""
  if [[ -n "$env_assoc_name" ]]; then
    local -n __env_assoc_ref=$env_assoc_name
    local_instance="${__env_assoc_ref[LOCAL_INSTANCE]:-}"
    repo_root_env="${__env_assoc_ref[REPO_ROOT]:-}"
  fi
  if [[ -z "$repo_root_env" ]]; then
    repo_root_env="$repo_root"
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

  local stdout_file=""
  local stderr_file=""
  if stdout_file=$(mktemp -t compose-config-stdout.XXXXXX 2>/dev/null) \
    && stderr_file=$(mktemp -t compose-config-stderr.XXXXXX 2>/dev/null); then
    LOCAL_INSTANCE="$local_instance" REPO_ROOT="$repo_root_env" \
      "${__compose_cmd_ref[@]}" config >"$stdout_file" 2>"$stderr_file" || compose_status=$?
  else
    local combined_output=""
    combined_output="$(LOCAL_INSTANCE="$local_instance" REPO_ROOT="$repo_root_env" \
      "${__compose_cmd_ref[@]}" config 2>&1)" || compose_status=$?
    if ((compose_status == 0)); then
      printf '%s\n' "$combined_output" >"$output_file"
      return 0
    fi
    compose_print_root_cause "$combined_output" __compose_cmd_ref
    rm -f "$output_file"
    return $compose_status
  fi

  if ((compose_status != 0)); then
    local compose_output=""
    if [[ -n "$stderr_file" && -f "$stderr_file" ]]; then
      compose_output=$(<"$stderr_file")
    fi
    if [[ -z "$compose_output" && -n "$stdout_file" && -f "$stdout_file" ]]; then
      compose_output=$(<"$stdout_file")
    fi
    if [[ -n "$compose_output" ]]; then
      compose_print_root_cause "$compose_output" __compose_cmd_ref
    fi
    rm -f "$stdout_file" "$stderr_file"
    rm -f "$output_file"
    return $compose_status
  fi

  if [[ -n "$stdout_file" && -f "$stdout_file" ]]; then
    mv "$stdout_file" "$output_file"
  fi
  rm -f "$stderr_file"

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
