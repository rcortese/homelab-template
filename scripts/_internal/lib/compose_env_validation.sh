#!/usr/bin/env bash
# shellcheck shell=bash

# Validate compose variable usage against loaded env vars.

COMPOSE_ENV_VALIDATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

compose_env_validation__load_python_runtime() {
  if [[ -n "${COMPOSE_ENV_VALIDATION_PYTHON_LOADED:-}" ]]; then
    return 0
  fi
  COMPOSE_ENV_VALIDATION_PYTHON_LOADED=1

  local shell_options
  shell_options="$(set +o)"
  # shellcheck source=scripts/_internal/lib/python_runtime.sh
  source "${COMPOSE_ENV_VALIDATION_DIR}/python_runtime.sh"
  eval "$shell_options"
}

compose_env_validation__extract_vars() {
  local repo_root="$1"
  local target_file="$2"
  local pattern_core='\$\{[A-Za-z_][A-Za-z0-9_]*([:-?][^}]*)?\}'
  local pattern_pcre="(?<!\\$)${pattern_core}"
  local pattern_ere="(^|[^$])${pattern_core}"

  if command -v rg >/dev/null 2>&1; then
    rg -o -P "$pattern_pcre" "$target_file" || true
    return 0
  fi

  if command -v grep >/dev/null 2>&1; then
    grep -oE "$pattern_ere" "$target_file" | sed 's/^[^$]//' || true
    return 0
  fi

  compose_env_validation__load_python_runtime
  if python_runtime__run_stdin "$repo_root" "" -- "$target_file" <<'PY'; then
import re
import sys
from pathlib import Path

pattern = re.compile(r"(?<!\$)\$\{[A-Za-z_][A-Za-z0-9_]*(?:[:-?][^}]*)?\}")
content = Path(sys.argv[1]).read_text(encoding="utf-8", errors="ignore")
for match in pattern.findall(content):
    print(match)
PY
    return 0
  fi

  echo "Error: unable to parse compose variables; rg, grep, and python are unavailable." >&2
  return 1
}

compose_env_validation__check() {
  local repo_root="$1"
  local compose_files_var="$2"
  local env_loaded_var="$3"
  local env_chain_list_var="$4"

  local -n compose_files_ref="$compose_files_var"
  local -n env_loaded_ref="$env_loaded_var"
  local -n env_chain_list_ref="$env_chain_list_var"

  declare -A missing_vars=()
  declare -A compose_vars=()

  local compose_file resolved_file raw_var
  for compose_file in "${compose_files_ref[@]}"; do
    resolved_file="$compose_file"
    if [[ "$resolved_file" != /* ]]; then
      resolved_file="$repo_root/$resolved_file"
    fi
    if [[ ! -f "$resolved_file" ]]; then
      continue
    fi
    local extracted_vars=""
    if ! extracted_vars="$(compose_env_validation__extract_vars "$repo_root" "$resolved_file")"; then
      return 1
    fi
    while IFS= read -r raw_var; do
      local requires_value=1
      if [[ "$raw_var" =~ ^\$\{[A-Za-z_][A-Za-z0-9_]*:\? ]]; then
        requires_value=1
      elif [[ "$raw_var" =~ ^\$\{[A-Za-z_][A-Za-z0-9_]*\? ]]; then
        requires_value=1
      elif [[ "$raw_var" =~ ^\$\{[A-Za-z_][A-Za-z0-9_]*[:-] ]]; then
        requires_value=0
      fi

      if ((requires_value == 0)); then
        continue
      fi

      raw_var="${raw_var#\${}"
      raw_var="${raw_var%}}"
      raw_var="${raw_var%%:*}"
      raw_var="${raw_var%%\?*}"
      raw_var="${raw_var%%-*}"
      if [[ -n "$raw_var" ]]; then
        compose_vars["$raw_var"]=1
      fi
    done <<<"$extracted_vars"
  done

  local compose_var
  for compose_var in "${!compose_vars[@]}"; do
    if [[ ! "$compose_var" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      continue
    fi
    if [[ "$compose_var" == "REPO_ROOT" || "$compose_var" == "LOCAL_INSTANCE" ]]; then
      continue
    fi
    if [[ -z ${env_loaded_ref[$compose_var]+x} && -z ${!compose_var+x} ]]; then
      missing_vars["$compose_var"]=1
    fi
  done

  if ((${#missing_vars[@]} > 0)); then
    printf 'Error: missing compose variables detected:\n' >&2
    for compose_var in "${!missing_vars[@]}"; do
      printf '  - %s\n' "$compose_var" >&2
    done
    if ((${#env_chain_list_ref[@]} > 0)); then
      printf 'Update one of the env files in the chain to define these keys:\n' >&2
      printf '  - %s\n' "${env_chain_list_ref[@]}" >&2
    else
      printf 'Provide values via --env-file/COMPOSE_ENV_FILES to resolve these keys.\n' >&2
    fi
    return 1
  fi

  return 0
}
