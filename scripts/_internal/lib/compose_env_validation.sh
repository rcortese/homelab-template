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

compose_env_validation__load_env_keys() {
  local env_file="$1"
  local output_var="$2"
  local -n output_ref="$output_var"

  output_ref=()
  if [[ ! -f "$env_file" ]]; then
    return 0
  fi

  local line key
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    if [[ "$line" == export\ * ]]; then
      line="${line#export }"
    fi
    if [[ "$line" != *"="* ]]; then
      continue
    fi
    key="${line%%=*}"
    [[ -z "$key" ]] && continue
    output_ref["$key"]=1
  done <"$env_file"
}

compose_env_validation__check() {
  local repo_root="$1"
  local compose_files_var="$2"
  local env_loaded_var="$3"
  local env_chain_list_var="$4"
  local instance_name="${5:-}"

  local -n compose_files_ref="$compose_files_var"
  local -n env_loaded_ref="$env_loaded_var"
  local -n env_chain_list_ref="$env_chain_list_var"

  local common_example="env/common.example.env"
  local instance_example=""
  local common_local="env/local/common.env"
  local instance_local=""
  if [[ -n "$instance_name" ]]; then
    instance_example="env/${instance_name}.example.env"
    instance_local="env/local/${instance_name}.env"
  fi

  declare -A missing_vars=()
  declare -A compose_vars=()
  declare -A common_example_keys=()
  declare -A instance_example_keys=()

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

  compose_env_validation__load_env_keys "$repo_root/$common_example" common_example_keys
  if [[ -n "$instance_example" ]]; then
    compose_env_validation__load_env_keys "$repo_root/$instance_example" instance_example_keys
  fi

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
    local -a missing_sorted=()
    mapfile -t missing_sorted < <(printf '%s\n' "${!missing_vars[@]}" | sort)
    for compose_var in "${missing_sorted[@]}"; do
      local expected_example="$common_example"
      local expected_local="$common_local"

      if [[ -n "${common_example_keys[$compose_var]:-}" ]]; then
        expected_example="$common_example"
        expected_local="$common_local"
      elif [[ -n "${instance_example_keys[$compose_var]:-}" && -n "$instance_example" ]]; then
        expected_example="$instance_example"
        expected_local="$instance_local"
      elif [[ -n "$instance_example" ]]; then
        expected_example="$instance_example"
        expected_local="$instance_local"
      fi

      printf '  - %s\n' "$compose_var" >&2
      printf '    expected source: %s\n' "$expected_example" >&2
      printf '    example line: %s=your-value\n' "$compose_var" >&2
      printf '    guidance: add the placeholder to %s and set the real value in %s.\n' \
        "$expected_example" \
        "$expected_local" >&2
    done
    if ((${#env_chain_list_ref[@]} > 0)); then
      printf 'Env chain (order):\n' >&2
      printf '  - %s\n' "${env_chain_list_ref[@]}" >&2
    else
      printf 'Provide values via --env-file/COMPOSE_ENV_FILES to resolve these keys.\n' >&2
    fi
    return 1
  fi

  return 0
}
