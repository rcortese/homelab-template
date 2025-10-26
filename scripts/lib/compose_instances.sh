#!/usr/bin/env bash

# Global variables exported by load_compose_instances / print_compose_instances:
#   BASE_COMPOSE_FILE          Relative path to the base compose file (e.g., compose/base.yml)
#   COMPOSE_INSTANCE_NAMES     Array with the list of detected instance names
#   COMPOSE_INSTANCE_FILES     Associative array mapping instance -> newline separated list of compose files
#                               (excluding the base file) that must be combined for the instance
#   COMPOSE_INSTANCE_ENV_LOCAL Associative array mapping instance -> relative env/local file (empty if absent)
#   COMPOSE_INSTANCE_ENV_TEMPLATES Associative array mapping instance -> relative env template file (empty if absent)
#   COMPOSE_INSTANCE_ENV_FILES Associative array mapping instance -> resolved env file (prefers env/local)
#   COMPOSE_INSTANCE_APP_NAMES Associative array mapping instance -> application directory name

append_instance_file() {
  local instance="$1"
  local file="$2"
  local existing="${COMPOSE_INSTANCE_FILES[$instance]-}"
  local entry

  if [[ -z "$existing" ]]; then
    COMPOSE_INSTANCE_FILES[$instance]="$file"
    return
  fi

  while IFS=$'\n' read -r entry; do
    if [[ "$entry" == "$file" ]]; then
      return
    fi
  done <<<"$existing"

  COMPOSE_INSTANCE_FILES[$instance]+=$'\n'"$file"
}

load_compose_instances() {
  local repo_root_input="${1:-}"
  local repo_root

  if [[ -n "$repo_root_input" ]]; then
    if ! repo_root="$(cd "$repo_root_input" 2>/dev/null && pwd)"; then
      echo "[!] Diretório do repositório inválido: $repo_root_input" >&2
      return 1
    fi
  else
    repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  fi

  local compose_dir_rel="compose"
  local apps_dir_rel="$compose_dir_rel/apps"
  local apps_dir="$repo_root/$apps_dir_rel"
  local env_dir_rel="env"
  local env_local_dir_rel="env/local"

  BASE_COMPOSE_FILE="$compose_dir_rel/base.yml"
  local base_compose_abs="$repo_root/$BASE_COMPOSE_FILE"
  if [[ ! -f "$base_compose_abs" ]]; then
    echo "[!] Arquivo base não encontrado: $BASE_COMPOSE_FILE" >&2
    return 1
  fi

  if [[ ! -d "$apps_dir" ]]; then
    echo "[!] Diretório de aplicações não encontrado: $apps_dir_rel" >&2
    return 1
  fi

  declare -gA COMPOSE_INSTANCE_FILES=()
  declare -gA COMPOSE_INSTANCE_ENV_LOCAL=()
  declare -gA COMPOSE_INSTANCE_ENV_TEMPLATES=()
  declare -gA COMPOSE_INSTANCE_ENV_FILES=()
  declare -gA COMPOSE_INSTANCE_APP_NAMES=()
  declare -ga COMPOSE_INSTANCE_NAMES=()

  shopt -s nullglob
  local -a app_dirs=()
  local app_dir
  for app_dir in "$apps_dir"/*; do
    [[ -d "$app_dir" ]] || continue
    app_dirs+=("$app_dir")
  done
  shopt -u nullglob

  if [[ ${#app_dirs[@]} -eq 0 ]]; then
    echo "[!] Nenhuma aplicação encontrada em $apps_dir_rel" >&2
    return 1
  fi

  if [[ ${#app_dirs[@]} -gt 0 ]]; then
    mapfile -t app_dirs < <(printf '%s\n' "${app_dirs[@]}" | sort)
  fi

  local -A seen_instances=()
  local app_name app_base_rel app_base_abs
  local instance_file filename instance_rel instance_abs instance

  for app_dir in "${app_dirs[@]}"; do
    app_name="${app_dir##*/}"
    app_base_rel="$apps_dir_rel/$app_name/base.yml"
    app_base_abs="$repo_root/$app_base_rel"

    if [[ ! -f "$app_base_abs" ]]; then
      echo "[!] Arquivo base da aplicação '$app_name' não encontrado: $app_base_rel" >&2
      return 1
    fi

    shopt -s nullglob
    local -a app_files=("$app_dir"/*.yml "$app_dir"/*.yaml)
    shopt -u nullglob

    local found_for_app=0
    for instance_file in "${app_files[@]}"; do
      filename="${instance_file##*/}"
      instance="${filename%.*}"
      if [[ "$instance" == "base" ]]; then
        continue
      fi

      ((found_for_app += 1))
      instance_rel="$apps_dir_rel/$app_name/$filename"
      instance_abs="$repo_root/$instance_rel"
      if [[ ! -f "$instance_abs" ]]; then
        echo "[!] Arquivo de instância não encontrado: $instance_rel" >&2
        return 1
      fi

      if [[ -n "${COMPOSE_INSTANCE_APP_NAMES[$instance]:-}" && "${COMPOSE_INSTANCE_APP_NAMES[$instance]}" != "$app_name" ]]; then
        echo "[!] Instância '$instance' encontrada em múltiplas aplicações ('$app_name' e '${COMPOSE_INSTANCE_APP_NAMES[$instance]}')." >&2
        return 1
      fi

      COMPOSE_INSTANCE_APP_NAMES[$instance]="$app_name"
      seen_instances[$instance]=1
      append_instance_file "$instance" "$app_base_rel"
      append_instance_file "$instance" "$instance_rel"
    done

    if [[ $found_for_app -eq 0 ]]; then
      echo "[!] Nenhuma instância encontrada para a aplicação '$app_name'." >&2
      return 1
    fi
  done

  if [[ ${#seen_instances[@]} -eq 0 ]]; then
    echo "[!] Nenhuma instância encontrada em $apps_dir_rel" >&2
    return 1
  fi

  local -a instance_names=()
  for instance in "${!seen_instances[@]}"; do
    instance_names+=("$instance")
  done

  if [[ ${#instance_names[@]} -gt 0 ]]; then
    mapfile -t instance_names < <(printf '%s\n' "${instance_names[@]}" | sort)
  fi

  COMPOSE_INSTANCE_NAMES=("${instance_names[@]}")

  local env_local_rel env_local_abs env_template_rel env_template_abs
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

    if [[ -f "$env_local_abs" ]]; then
      COMPOSE_INSTANCE_ENV_FILES[$instance]="$env_local_rel"
    elif [[ -f "$env_template_abs" ]]; then
      COMPOSE_INSTANCE_ENV_FILES[$instance]="$env_template_rel"
    else
      echo "[!] Nenhum arquivo .env encontrado para instância '$instance'." >&2
      echo "    Esperado: $env_local_rel ou $env_template_rel" >&2
      return 1
    fi
  done

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
    COMPOSE_INSTANCE_ENV_FILES \
    COMPOSE_INSTANCE_APP_NAMES
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  print_compose_instances "$@"
fi
