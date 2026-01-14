#!/usr/bin/env bash

# Helpers to format validation output.

validate_executor_print_root_cause() {
  if [[ $# -lt 2 ]]; then
    echo "validate_executor_print_root_cause: expected <compose_output> <files_ref>" >&2
    return 64
  fi

  local compose_output="$1"
  local files_name="$2"
  local -n __files_ref=$files_name

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

  if ((${#__files_ref[@]} > 0)); then
    echo "   compose plan order:" >&2
    local idx
    for idx in "${!__files_ref[@]}"; do
      echo "     $((idx + 1)). ${__files_ref[$idx]}" >&2
    done
  fi
}
