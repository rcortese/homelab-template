#!/usr/bin/env bash

compose_env_map__resolve_repo_root() {
  local repo_root_input="${1:-}"
  local script_dir

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  if [[ -n "$repo_root_input" ]]; then
    if ! (cd "$repo_root_input" 2>/dev/null); then
      echo "[!] Diretório do repositório inválido: $repo_root_input" >&2
      return 1
    fi
    (cd "$repo_root_input" && pwd)
    return 0
  fi

  (cd "$script_dir/../.." && pwd)
}

load_compose_env_map() {
  if ! declare -p COMPOSE_INSTANCE_NAMES >/dev/null 2>&1; then
    echo "[!] COMPOSE_INSTANCE_NAMES não inicializado. Execute load_compose_discovery primeiro." >&2
    return 1
  fi

  if ! declare -p COMPOSE_INSTANCE_FILES >/dev/null 2>&1; then
    echo "[!] COMPOSE_INSTANCE_FILES não inicializado. Execute load_compose_discovery primeiro." >&2
    return 1
  fi

  local repo_root
  if ! repo_root="$(compose_env_map__resolve_repo_root "$1")"; then
    return 1
  fi

  local env_dir_rel="env"
  local env_local_dir_rel="env/local"

  declare -ga COMPOSE_ENV_GLOBAL_FILES=()
  declare -gA COMPOSE_INSTANCE_ENV_LOCAL=()
  declare -gA COMPOSE_INSTANCE_ENV_TEMPLATES=()
  declare -gA COMPOSE_INSTANCE_ENV_FILES=()

  local global_env_local_rel="$env_local_dir_rel/common.env"
  local global_env_template_rel="$env_dir_rel/common.example.env"

  if [[ -f "$repo_root/$global_env_local_rel" ]]; then
    COMPOSE_ENV_GLOBAL_FILES=("$global_env_local_rel")
  elif [[ -f "$repo_root/$global_env_template_rel" ]]; then
    COMPOSE_ENV_GLOBAL_FILES=("$global_env_template_rel")
  else
    COMPOSE_ENV_GLOBAL_FILES=()
  fi

  local instance env_local_rel env_local_abs env_template_rel env_template_abs
  for instance in "${COMPOSE_INSTANCE_NAMES[@]}"; do
    env_local_rel="$env_local_dir_rel/${instance}.env"
    env_local_abs="$repo_root/$env_local_rel"
    env_template_rel="$env_dir_rel/${instance}.example.env"
    env_template_abs="$repo_root/$env_template_rel"

    if [[ -z "${COMPOSE_INSTANCE_FILES[$instance]:-}" ]]; then
      echo "[!] Nenhum arquivo compose registrado para a instância '$instance'." >&2
      return 1
    fi

    if [[ -f "$env_local_abs" ]]; then
      COMPOSE_INSTANCE_ENV_LOCAL[$instance]="$env_local_rel"
    else
      COMPOSE_INSTANCE_ENV_LOCAL[$instance]=""
    fi

    if [[ -f "$env_template_abs" ]]; then
      COMPOSE_INSTANCE_ENV_TEMPLATES[$instance]="$env_template_rel"
    else
      COMPOSE_INSTANCE_ENV_TEMPLATES[$instance]=""
    fi

    local -a env_files_list=("${COMPOSE_ENV_GLOBAL_FILES[@]}")

    if [[ -f "$env_local_abs" ]]; then
      env_files_list+=("$env_local_rel")
    elif [[ -f "$env_template_abs" ]]; then
      env_files_list+=("$env_template_rel")
    else
      echo "[!] Nenhum arquivo .env encontrado para instância '$instance'." >&2
      echo "    Esperado: $env_local_rel ou $env_template_rel" >&2
      return 1
    fi

    if ((${#env_files_list[@]} > 0)); then
      local joined=""
      local entry
      for entry in "${env_files_list[@]}"; do
        if [[ -n "$joined" ]]; then
          joined+=$'\n'
        fi
        joined+="$entry"
      done
      COMPOSE_INSTANCE_ENV_FILES[$instance]="$joined"
    else
      COMPOSE_INSTANCE_ENV_FILES[$instance]=""
    fi
  done

  # Touch globals to satisfy shellcheck: consumers read these arrays after sourcing.
  : "${COMPOSE_ENV_GLOBAL_FILES[@]}"
  : "${COMPOSE_INSTANCE_ENV_LOCAL[@]}"
  : "${COMPOSE_INSTANCE_ENV_TEMPLATES[@]}"
  : "${COMPOSE_INSTANCE_ENV_FILES[@]}"

  return 0
}
