#!/usr/bin/env bash

compose_discovery__resolve_repo_root() {
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

compose_discovery__append_instance_file() {
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

load_compose_discovery() {
  local repo_root
  if ! repo_root="$(compose_discovery__resolve_repo_root "$1")"; then
    return 1
  fi

  local compose_dir_rel="compose"
  local apps_dir_rel="$compose_dir_rel/apps"
  local apps_dir="$repo_root/$apps_dir_rel"

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

      local existing_apps="${COMPOSE_INSTANCE_APP_NAMES[$instance]:-}"
      if [[ -z "$existing_apps" ]]; then
        COMPOSE_INSTANCE_APP_NAMES[$instance]="$app_name"
      else
        local already_listed=0
        while IFS=$'\n' read -r existing_app; do
          if [[ "$existing_app" == "$app_name" ]]; then
            already_listed=1
            break
          fi
        done <<<"$existing_apps"

        if [[ $already_listed -eq 0 ]]; then
          COMPOSE_INSTANCE_APP_NAMES[$instance]+=$'\n'"$app_name"
        fi
      fi
      seen_instances[$instance]=1
      compose_discovery__append_instance_file "$instance" "$instance_rel"
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

  return 0
}
