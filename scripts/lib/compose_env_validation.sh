#!/usr/bin/env bash
# shellcheck shell=bash

# Validate compose variable usage against loaded env vars.

compose_env_validation__check() {
  local repo_root="$1"
  local compose_files_var="$2"
  local env_loaded_var="$3"
  local env_chain_list_var="$4"

  local -n compose_files_list="$compose_files_var"
  local -n env_loaded="$env_loaded_var"
  local -n env_chain_list="$env_chain_list_var"

  declare -A missing_vars=()
  declare -A compose_vars=()

  local compose_file resolved_file raw_var
  for compose_file in "${compose_files_list[@]}"; do
    resolved_file="$compose_file"
    if [[ "$resolved_file" != /* ]]; then
      resolved_file="$repo_root/$resolved_file"
    fi
    if [[ ! -f "$resolved_file" ]]; then
      continue
    fi
    while IFS= read -r raw_var; do
      raw_var="${raw_var#\${}"
      raw_var="${raw_var%}}"
      raw_var="${raw_var%%:*}"
      raw_var="${raw_var%%\?*}"
      raw_var="${raw_var%%-*}"
      if [[ -n "$raw_var" ]]; then
        compose_vars["$raw_var"]=1
      fi
    done < <(rg -o -P '\$\{[A-Za-z_][A-Za-z0-9_]*([:-?][^}]*)?\}' "$resolved_file" || true)
  done

  local compose_var
  for compose_var in "${!compose_vars[@]}"; do
    if [[ "$compose_var" == "REPO_ROOT" || "$compose_var" == "LOCAL_INSTANCE" ]]; then
      continue
    fi
    if [[ -z ${env_loaded[$compose_var]+x} && -z ${!compose_var+x} ]]; then
      missing_vars["$compose_var"]=1
    fi
  done

  if ((${#missing_vars[@]} > 0)); then
    printf 'Error: missing compose variables detected:\n' >&2
    for compose_var in "${!missing_vars[@]}"; do
      printf '  - %s\n' "$compose_var" >&2
    done
    if ((${#env_chain_list[@]} > 0)); then
      printf 'Update one of the env files in the chain to define these keys:\n' >&2
      printf '  - %s\n' "${env_chain_list[@]}" >&2
    else
      printf 'Provide values via --env-file/COMPOSE_ENV_FILES to resolve these keys.\n' >&2
    fi
    return 1
  fi

  return 0
}
