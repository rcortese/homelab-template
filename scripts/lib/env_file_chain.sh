#!/usr/bin/env bash
# shellcheck shell=bash

# Utilities to parse and resolve the env-file chain used by compose helpers.

env_file_chain__parse_list() {
  local raw_input="${1:-}"
  local -n __out_ref="$2"

  __out_ref=()
  if [[ -z "$raw_input" ]]; then
    return
  fi

  local sanitized="${raw_input//$'\n'/ }"
  sanitized="${sanitized//,/ }"

  local token
  for token in $sanitized; do
    [[ -z "$token" ]] && continue
    __out_ref+=("$token")
  done
}

env_file_chain__dedupe_preserve_order() {
  local -n __input_ref="$1"
  local -n __out_ref="$2"

  declare -A __seen=()
  __out_ref=()

  local item
  for item in "${__input_ref[@]}"; do
    [[ -z "$item" ]] && continue
    if [[ -z "${__seen[$item]:-}" ]]; then
      __seen[$item]=1
      __out_ref+=("$item")
    fi
  done
}

env_file_chain__resolve_explicit() {
  local explicit_raw="${1:-}"
  local metadata_raw="${2:-}"
  local out_name="$3"

  declare -a __assembled=()

  if [[ -n "$explicit_raw" ]]; then
    env_file_chain__parse_list "$explicit_raw" __assembled
  elif [[ -n "$metadata_raw" ]]; then
    env_file_chain__parse_list "$metadata_raw" __assembled
  fi

  env_file_chain__dedupe_preserve_order __assembled "$out_name"
}

env_file_chain__defaults() {
  local repo_root="$1"
  local instance="$2"
  local -n __out_ref="$3"

  __out_ref=()

  if [[ -f "$repo_root/env/local/common.env" ]]; then
    __out_ref+=("env/local/common.env")
  elif [[ -f "$repo_root/env/common.example.env" ]]; then
    __out_ref+=("env/common.example.env")
  fi

  if [[ -z "$instance" ]]; then
    return
  fi

  local instance_local="env/local/${instance}.env"
  if [[ -f "$repo_root/$instance_local" ]]; then
    __out_ref+=("$instance_local")
    return
  fi

  local instance_template="env/${instance}.example.env"
  if [[ -f "$repo_root/$instance_template" ]]; then
    __out_ref+=("$instance_template")
  fi
}

env_file_chain__to_absolute() {
  local repo_root="$1"
  local -n __rel_ref="$2"
  local -n __out_ref="$3"

  __out_ref=()
  local item
  for item in "${__rel_ref[@]}"; do
    [[ -z "$item" ]] && continue
    if [[ "$item" != /* ]]; then
      __out_ref+=("$repo_root/$item")
    else
      __out_ref+=("$item")
    fi
  done
}

env_file_chain__join() {
  local delimiter="$1"
  shift
  local -n __input_ref="$1"
  local joined=""
  local item
  for item in "${__input_ref[@]}"; do
    [[ -z "$item" ]] && continue
    if [[ -z "$joined" ]]; then
      joined="$item"
    else
      joined+="$delimiter$item"
    fi
  done
  printf '%s' "$joined"
}
