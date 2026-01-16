#!/usr/bin/env bash

format_cmd() {
  local output=""
  local arg
  for arg in "$@"; do
    output+="$(printf '%q ' "$arg")"
  done
  printf '%s' "${output% }"
}

run_step() {
  local description="$1"
  shift
  local cmd_display=""
  local -a cmd_exec=()

  if [[ $# -eq 0 ]]; then
    echo "[!] No command provided to run_step." >&2
    return 1
  fi

  if [[ $# -eq 1 ]]; then
    cmd_display="$1"
    cmd_exec=(bash -lc "$1")
  else
    cmd_exec=("$@")
    cmd_display="$(format_cmd "${cmd_exec[@]}")"
  fi

  echo "[*] ${description}"
  echo "    ${cmd_display}"

  local dry_run="${STEP_RUNNER_DRY_RUN:-0}"
  if [[ "$dry_run" -eq 1 ]]; then
    return 0
  fi

  "${cmd_exec[@]}"
  local status=$?
  if [[ $status -ne 0 ]]; then
    echo "[!] Failed to execute step: ${description}" >&2
    return "$status"
  fi

  return 0
}
