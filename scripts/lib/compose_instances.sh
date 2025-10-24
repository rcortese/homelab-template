#!/usr/bin/env bash

# Global variables exported by load_compose_instances / print_compose_instances:
#   BASE_COMPOSE_FILE          Relative path to the base compose file (e.g., compose/base.yml)
#   COMPOSE_INSTANCE_NAMES     Array with the list of detected instance names
#   COMPOSE_INSTANCE_FILES     Associative array mapping instance -> relative compose override file
#   COMPOSE_INSTANCE_ENV_LOCAL Associative array mapping instance -> relative env/local file (empty if absent)
#   COMPOSE_INSTANCE_ENV_TEMPLATES Associative array mapping instance -> relative env template file (empty if absent)
#   COMPOSE_INSTANCE_ENV_FILES Associative array mapping instance -> resolved env file (prefers env/local)

load_compose_instances() {
  local repo_root_input="${1:-}"
  local repo_root

  if [[ -n "$repo_root_input" ]]; then
    if ! repo_root="$(cd "$repo_root_input" 2>/dev/null && pwd)"; then
      echo "[!] Diretório do repositório inválido: $repo_root_input" >&2
      return 1
    fi
  else
    repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  fi

  local compose_dir_rel="compose"
  local compose_dir="$repo_root/$compose_dir_rel"
  local env_dir_rel="env"
  local env_local_dir_rel="env/local"

  BASE_COMPOSE_FILE="$compose_dir_rel/base.yml"
  local base_compose_abs="$repo_root/$BASE_COMPOSE_FILE"
  if [[ ! -f "$base_compose_abs" ]]; then
    echo "[!] Arquivo base não encontrado: $BASE_COMPOSE_FILE" >&2
    return 1
  fi

  declare -gA COMPOSE_INSTANCE_FILES=()
  declare -gA COMPOSE_INSTANCE_ENV_LOCAL=()
  declare -gA COMPOSE_INSTANCE_ENV_TEMPLATES=()
  declare -gA COMPOSE_INSTANCE_ENV_FILES=()
  declare -ga COMPOSE_INSTANCE_NAMES=()

  shopt -s nullglob
  local compose_files=()
  for candidate in "$compose_dir"/*.yml "$compose_dir"/*.yaml; do
    compose_files+=("$candidate")
  done
  shopt -u nullglob

  local found=0
  local name file filename env_local_rel env_local_abs env_template_rel env_template_abs
  for file in "${compose_files[@]}"; do
    filename="${file##*/}"
    name="${filename%%.*}"
    if [[ "$name" == "base" ]]; then
      continue
    fi

    ((found+=1))
    env_local_rel="$env_local_dir_rel/${name}.env"
    env_local_abs="$repo_root/$env_local_rel"
    env_template_rel="$env_dir_rel/${name}.example.env"
    env_template_abs="$repo_root/$env_template_rel"

    COMPOSE_INSTANCE_FILES["$name"]="$compose_dir_rel/$filename"

    if [[ -f "$env_local_abs" ]]; then
      COMPOSE_INSTANCE_ENV_LOCAL["$name"]="$env_local_rel"
    else
      COMPOSE_INSTANCE_ENV_LOCAL["$name"]=""
    fi

    if [[ -f "$env_template_abs" ]]; then
      COMPOSE_INSTANCE_ENV_TEMPLATES["$name"]="$env_template_rel"
    else
      COMPOSE_INSTANCE_ENV_TEMPLATES["$name"]=""
    fi

    if [[ -f "$env_local_abs" ]]; then
      COMPOSE_INSTANCE_ENV_FILES["$name"]="$env_local_rel"
    elif [[ -f "$env_template_abs" ]]; then
      COMPOSE_INSTANCE_ENV_FILES["$name"]="$env_template_rel"
    else
      echo "[!] Nenhum arquivo .env encontrado para instância '$name'." >&2
      echo "    Esperado: $env_local_rel ou $env_template_rel" >&2
      return 1
    fi

    COMPOSE_INSTANCE_NAMES+=("$name")
  done

  if [[ $found -eq 0 ]]; then
    echo "[!] Nenhuma instância encontrada em $compose_dir_rel" >&2
    return 1
  fi

  return 0
}

print_compose_instances() {
  local repo_root_input="${1:-}"

  if ! load_compose_instances "$repo_root_input"; then
    return 1
  fi

  declare -p \
    BASE_COMPOSE_FILE \
    COMPOSE_INSTANCE_NAMES \
    COMPOSE_INSTANCE_FILES \
    COMPOSE_INSTANCE_ENV_LOCAL \
    COMPOSE_INSTANCE_ENV_TEMPLATES \
    COMPOSE_INSTANCE_ENV_FILES
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  print_compose_instances "$@"
fi
