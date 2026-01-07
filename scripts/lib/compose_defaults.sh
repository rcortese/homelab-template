#!/usr/bin/env bash
set -euo pipefail

# Configure docker compose defaults based on the provided instance name.
# Arguments:
#   $1 - Instance name (optional).
#   $2 - Base directory for compose/env files (defaults to current directory).

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib/compose_command.sh
source "${LIB_DIR}/compose_command.sh"

# shellcheck source=scripts/lib/env_file_chain.sh
source "${LIB_DIR}/env_file_chain.sh"

setup_compose_defaults() {
  local instance="${1:-}"
  local base_dir="${2:-.}"
  local base_fs
  local compose_root="docker-compose.yml"
  local compose_root_path=""

  declare -g COMPOSE_FILES=""
  declare -g COMPOSE_ENV_FILES="${COMPOSE_ENV_FILES:-}"
  declare -ga COMPOSE_CMD=()

  if [[ "$base_dir" == "." ]]; then
    base_fs="$(pwd)"
  else
    if ! base_fs="$(cd "$base_dir" 2>/dev/null && pwd)"; then
      base_fs="$base_dir"
    fi
  fi

  local metadata_loaded=0
  local compose_metadata=""
  if [[ -n "$instance" ]]; then
    if compose_metadata="$("${LIB_DIR}/compose_instances.sh" "$base_fs")"; then
      eval "$compose_metadata"
      metadata_loaded=1
    fi
  fi

  compose_root_path="${base_fs%/}/$compose_root"
  if [[ ! -f "$compose_root_path" ]]; then
    echo "[!] Missing ${compose_root} in ${base_fs}. Run scripts/build_compose_file.sh to generate it." >&2
    return 1
  fi

  COMPOSE_FILES="$compose_root"

  local env_chain_input="${COMPOSE_ENV_FILES:-}"
  if [[ -z "$env_chain_input" && -n "$instance" && $metadata_loaded -eq 1 && -n "${COMPOSE_INSTANCE_ENV_FILES[$instance]:-}" ]]; then
    env_chain_input="${COMPOSE_INSTANCE_ENV_FILES[$instance]}"
  fi

  declare -a env_files_rel=()
  local env_chain_output=""
  if ! env_chain_output="$(env_file_chain__resolve_explicit "$env_chain_input" "$base_fs" "$instance")"; then
    return 1
  fi
  if [[ -n "$env_chain_output" ]]; then
    mapfile -t env_files_rel <<<"$env_chain_output"
  fi

  declare -a env_files_abs=()
  if ((${#env_files_rel[@]} > 0)); then
    mapfile -t env_files_abs < <(
      env_file_chain__to_absolute "$base_fs" "${env_files_rel[@]}"
    )
  fi

  if ((${#env_files_abs[@]} > 0)); then
    COMPOSE_ENV_FILES="$(printf '%s\n' "${env_files_abs[@]}")"
    COMPOSE_ENV_FILES="${COMPOSE_ENV_FILES%$'\n'}"
  else
    COMPOSE_ENV_FILES=""
  fi

  local -a compose_cmd_resolved=()
  if compose_resolve_command compose_cmd_resolved; then
    COMPOSE_CMD=("${compose_cmd_resolved[@]}")
  else
    return $?
  fi

  if ((${#env_files_abs[@]} > 0)); then
    local env_file_path
    for env_file_path in "${env_files_abs[@]}"; do
      COMPOSE_CMD+=(--env-file "$env_file_path")
    done
  fi

  COMPOSE_CMD+=(-f "$compose_root_path")
}

main() {
  local instance="${1:-}"
  local base_dir="${2:-.}"

  setup_compose_defaults "$instance" "$base_dir"

  declare -p COMPOSE_FILES COMPOSE_ENV_FILES COMPOSE_CMD
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
