#!/usr/bin/env bash
# Helper to execute Python code preferring Docker over local runtimes.
# shellcheck shell=bash
set -euo pipefail

PYTHON_RUNTIME_IMAGE="${PYTHON_RUNTIME_IMAGE:-python:3.11-slim}"
PYTHON_RUNTIME_DOCKER_BIN="${PYTHON_RUNTIME_DOCKER_BIN:-docker}"
PYTHON_RUNTIME_REQUIREMENTS_FILE="${PYTHON_RUNTIME_REQUIREMENTS_FILE:-}" # optional override
PYTHON_RUNTIME_SKIP_REQUIREMENTS="${PYTHON_RUNTIME_SKIP_REQUIREMENTS:-0}"

python_runtime__resolve_requirements() {
  local repo_root="$1"
  if [[ -n "$PYTHON_RUNTIME_REQUIREMENTS_FILE" ]]; then
    printf '%s' "$PYTHON_RUNTIME_REQUIREMENTS_FILE"
    return 0
  fi

  local default_req="${repo_root%/}/requirements-dev.txt"
  if [[ -f "$default_req" ]]; then
    printf '%s' "$default_req"
  else
    printf ''
  fi
}

python_runtime__build_docker_prefix() {
  local repo_root="$1"
  local env_vars_raw="$2"
  shift 2 || true

  local -a docker_cmd=("$PYTHON_RUNTIME_DOCKER_BIN" run --rm -i)
  docker_cmd+=("-v" "${repo_root}:${repo_root}" "-w" "${PWD}")
  docker_cmd+=("--env" "PYTHONUNBUFFERED=1")

  local var_name
  for var_name in $env_vars_raw; do
    if [[ -n "${!var_name-}" ]]; then
      docker_cmd+=("--env" "${var_name}=${!var_name}")
    fi
  done

  docker_cmd+=("$PYTHON_RUNTIME_IMAGE")
  printf '%s\n' "${docker_cmd[@]}"
}

python_runtime__install_local_requirements() {
  local python_bin="$1"
  local requirements="$2"

  if [[ -z "$requirements" || ! -f "$requirements" || "$PYTHON_RUNTIME_SKIP_REQUIREMENTS" == "1" ]]; then
    return 0
  fi

  "$python_bin" -m pip install --root-user-action=ignore --quiet --no-cache-dir -r "$requirements" >/dev/null
}

python_runtime__run() {
  local repo_root="$1"
  local env_vars_raw="$2"
  shift 2 || true
  if [[ "$1" == "--" ]]; then
    shift || true
  fi
  local -a py_args=("$@")

  local python_bin=""
  if command -v "$PYTHON_RUNTIME_DOCKER_BIN" >/dev/null 2>&1; then
    local requirements
    requirements="$(python_runtime__resolve_requirements "$repo_root")"
    mapfile -t docker_cmd < <(python_runtime__build_docker_prefix "$repo_root" "$env_vars_raw")
    if [[ -n "$requirements" && -f "$requirements" && "$PYTHON_RUNTIME_SKIP_REQUIREMENTS" != "1" ]]; then
      "${docker_cmd[@]}" bash -c "PIP_DISABLE_PIP_VERSION_CHECK=1 pip install --root-user-action=ignore --quiet --no-cache-dir -r '$requirements' >/dev/null && python \"\$@\"" bash "${py_args[@]}"
    else
      "${docker_cmd[@]}" python "${py_args[@]}"
    fi
    return $?
  fi

  if command -v python3 >/dev/null 2>&1; then
    python_bin="python3"
  elif command -v python >/dev/null 2>&1; then
    python_bin="python"
  else
    echo "Error: nenhum runtime Python encontrado nem Docker disponível." >&2
    return 1
  fi

  local requirements
  requirements="$(python_runtime__resolve_requirements "$repo_root")"
  python_runtime__install_local_requirements "$python_bin" "$requirements"

  "$python_bin" "${py_args[@]}"
}

python_runtime__run_stdin() {
  local repo_root="$1"
  local env_vars_raw="$2"
  shift 2 || true
  if [[ "$1" == "--" ]]; then
    shift || true
  fi
  local -a py_args=("$@")

  local python_bin=""
  if command -v "$PYTHON_RUNTIME_DOCKER_BIN" >/dev/null 2>&1; then
    local requirements
    requirements="$(python_runtime__resolve_requirements "$repo_root")"
    mapfile -t docker_cmd < <(python_runtime__build_docker_prefix "$repo_root" "$env_vars_raw")
    if [[ -n "$requirements" && -f "$requirements" && "$PYTHON_RUNTIME_SKIP_REQUIREMENTS" != "1" ]]; then
      cat | "${docker_cmd[@]}" bash -c "PIP_DISABLE_PIP_VERSION_CHECK=1 pip install --root-user-action=ignore --quiet --no-cache-dir -r '$requirements' >/dev/null && python - \"\$@\"" bash "${py_args[@]}"
    else
      cat | "${docker_cmd[@]}" python - "${py_args[@]}"
    fi
    return $?
  fi

  if command -v python3 >/dev/null 2>&1; then
    python_bin="python3"
  elif command -v python >/dev/null 2>&1; then
    python_bin="python"
  else
    echo "Error: nenhum runtime Python encontrado nem Docker disponível." >&2
    return 1
  fi

  local requirements
  requirements="$(python_runtime__resolve_requirements "$repo_root")"
  python_runtime__install_local_requirements "$python_bin" "$requirements"

  cat | "$python_bin" - "${py_args[@]}"
}
