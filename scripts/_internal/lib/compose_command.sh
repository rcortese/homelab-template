#!/usr/bin/env bash
# Shared helpers for resolving docker compose command invocations.

compose_resolve_command() {
  if [[ $# -lt 1 ]]; then
    echo "compose_resolve_command: missing destination nameref" >&2
    return 64
  fi

  local -n __compose_cmd_out=$1
  shift || true

  local override_value="${1:-${DOCKER_COMPOSE_BIN:-}}"
  local -a resolved_cmd=()

  if [[ -n "$override_value" ]]; then
    # Allow overrides such as "docker --context remote compose" or "docker-compose".
    # shellcheck disable=SC2206
    resolved_cmd=($override_value)
  else
    resolved_cmd=(docker compose)
  fi

  if ((${#resolved_cmd[@]} == 0)); then
    echo "Error: docker compose command is empty." >&2
    return 127
  fi

  if ! command -v "${resolved_cmd[0]}" >/dev/null 2>&1; then
    echo "Error: ${resolved_cmd[0]} is not available. Set DOCKER_COMPOSE_BIN if needed." >&2
    return 127
  fi

  __compose_cmd_out=("${resolved_cmd[@]}")
  return 0
}
