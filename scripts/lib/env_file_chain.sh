#!/usr/bin/env bash
# shellcheck shell=bash

# Utilities to parse and resolve the env-file chain used by compose helpers.

env_file_chain__parse_list() {
  local raw_input="${1:-}"

  if [[ -z "$raw_input" ]]; then
    return 0
  fi

  local sanitized="${raw_input//$'\n'/ }"
  sanitized="${sanitized//,/ }"

  local token
  for token in $sanitized; do
    [[ -z "$token" ]] && continue
    printf '%s\n' "$token"
  done
}

env_file_chain__dedupe_preserve_order() {
  declare -A seen=()
  local item
  for item in "$@"; do
    [[ -z "$item" ]] && continue
    if [[ -z "${seen[$item]:-}" ]]; then
      seen[$item]=1
      printf '%s\n' "$item"
    fi
  done
}

env_file_chain__resolve_explicit() {
  local explicit_raw="${1:-}"
  local repo_root="${2:-}"
  local instance="${3:-}"

  local -a assembled=()

  if [[ -n "$explicit_raw" ]]; then
    mapfile -t assembled < <(env_file_chain__parse_list "$explicit_raw")
    if ((${#assembled[@]} > 0)); then
      env_file_chain__dedupe_preserve_order "${assembled[@]}"
      return 0
    fi
  fi

  env_file_chain__defaults "$repo_root" "$instance"
}

env_file_chain__defaults() {
  local repo_root="$1"
  local instance="$2"
  local missing=0
  local -a defaults=()

  if [[ -f "$repo_root/env/local/common.env" ]]; then
    defaults+=("env/local/common.env")
  else
    echo "[!] Missing env/local/common.env." >&2
    if [[ -f "$repo_root/env/common.example.env" ]]; then
      echo "    Copy the template before continuing:" >&2
      echo "    mkdir -p env/local" >&2
      echo "    cp env/common.example.env env/local/common.env" >&2
    else
      echo "    Template env/common.example.env was not found." >&2
    fi
    missing=1
  fi

  if [[ -z "$instance" ]]; then
    if ((missing == 1)); then
      return 1
    fi
    printf '%s\n' "${defaults[@]}"
    return 0
  fi

  local instance_local="env/local/${instance}.env"
  if [[ -f "$repo_root/$instance_local" ]]; then
    defaults+=("$instance_local")
  else
    echo "[!] Missing env/local/${instance}.env." >&2
    if [[ -f "$repo_root/env/${instance}.example.env" ]]; then
      echo "    Copy the template before continuing:" >&2
      echo "    mkdir -p env/local" >&2
      echo "    cp env/${instance}.example.env env/local/${instance}.env" >&2
    else
      echo "    Template env/${instance}.example.env was not found." >&2
    fi
    missing=1
  fi

  if ((missing == 1)); then
    return 1
  fi

  printf '%s\n' "${defaults[@]}"
}

env_file_chain__to_absolute() {
  local repo_root="$1"
  shift

  local item
  for item in "$@"; do
    [[ -z "$item" ]] && continue
    if [[ "$item" != /* ]]; then
      printf '%s\n' "$repo_root/$item"
    else
      printf '%s\n' "$item"
    fi
  done
}

env_file_chain__join() {
  local delimiter="$1"
  shift

  local joined=""
  local item
  for item in "$@"; do
    [[ -z "$item" ]] && continue
    if [[ -z "$joined" ]]; then
      joined="$item"
    else
      joined+="$delimiter$item"
    fi
  done

  printf '%s' "$joined"
}
