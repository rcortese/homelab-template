#!/usr/bin/env bash

# shellcheck source=scripts/lib/compose_paths.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/compose_paths.sh"

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
  if ! repo_root="$(compose_common__resolve_repo_root "$1")"; then
    return 1
  fi

  local compose_dir_rel="compose"
  local apps_dir_rel="$compose_dir_rel/apps"
  local apps_dir="$repo_root/$apps_dir_rel"
  local env_dir_rel="env"
  local env_local_dir_rel="$env_dir_rel/local"

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
  declare -gA COMPOSE_APP_BASE_FILES=()
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
  local -a apps_without_overrides=()
  local app_name app_base_rel app_base_abs
  local instance_file filename instance_rel instance_abs instance

  for app_dir in "${app_dirs[@]}"; do
    app_name="${app_dir##*/}"
    app_base_rel="$apps_dir_rel/$app_name/base.yml"
    app_base_abs="$repo_root/$app_base_rel"

    if [[ -f "$app_base_abs" ]]; then
      COMPOSE_APP_BASE_FILES[$app_name]="$app_base_rel"
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

    if [[ $found_for_app -eq 0 && -f "$app_base_abs" ]]; then
      apps_without_overrides+=("$app_name")
    fi
  done

  shopt -s nullglob
  local -a top_level_candidates=("$repo_root/$compose_dir_rel"/*.yml "$repo_root/$compose_dir_rel"/*.yaml)
  shopt -u nullglob

  local instance_file candidate_name candidate_instance
  for instance_file in "${top_level_candidates[@]}"; do
    [[ -f "$instance_file" ]] || continue
    candidate_name="${instance_file##*/}"
    candidate_instance="${candidate_name%.*}"
    if [[ "$candidate_instance" == "base" ]]; then
      continue
    fi

    seen_instances[$candidate_instance]=1
    compose_discovery__append_instance_file "$candidate_instance" "$compose_dir_rel/$candidate_name"
  done

  declare -A known_instances=()
  for instance in "${!seen_instances[@]}"; do
    known_instances[$instance]=1
  done

  shopt -s nullglob
  local env_candidate env_instance
  for env_candidate in "$repo_root/$env_dir_rel"/*.example.env; do
    env_instance="${env_candidate##*/}"
    env_instance="${env_instance%.example.env}"
    if [[ -n "$env_instance" && "$env_instance" != "common" ]]; then
      known_instances[$env_instance]=1
    fi
  done

  if [[ -d "$repo_root/$env_local_dir_rel" ]]; then
    for env_candidate in "$repo_root/$env_local_dir_rel"/*.env; do
      env_instance="${env_candidate##*/}"
      env_instance="${env_instance%.env}"
      if [[ -n "$env_instance" && "$env_instance" != "common" ]]; then
        known_instances[$env_instance]=1
      fi
    done
  fi
  shopt -u nullglob

  if [[ ${#known_instances[@]} -eq 0 ]]; then
    echo "[!] Nenhuma instância encontrada em $apps_dir_rel ou $env_dir_rel" >&2
    return 1
  fi

  local -a instance_names=()
  for instance in "${!known_instances[@]}"; do
    instance_names+=("$instance")
  done

  if [[ ${#instance_names[@]} -gt 0 ]]; then
    mapfile -t instance_names < <(printf '%s\n' "${instance_names[@]}" | sort)
  fi

  for instance in "${instance_names[@]}"; do
    if [[ ! -v COMPOSE_INSTANCE_FILES[$instance] ]]; then
      COMPOSE_INSTANCE_FILES[$instance]=""
    fi
  done

  if [[ ${#apps_without_overrides[@]} -gt 0 ]]; then
    local app_without_override existing_apps already_listed
    for instance in "${instance_names[@]}"; do
      for app_without_override in "${apps_without_overrides[@]}"; do
        existing_apps="${COMPOSE_INSTANCE_APP_NAMES[$instance]:-}"
        already_listed=0
        if [[ -n "$existing_apps" ]]; then
          while IFS=$'\n' read -r existing_app; do
            if [[ "$existing_app" == "$app_without_override" ]]; then
              already_listed=1
              break
            fi
          done <<<"$existing_apps"
        fi

        if [[ $already_listed -eq 0 ]]; then
          if [[ -z "$existing_apps" ]]; then
            COMPOSE_INSTANCE_APP_NAMES[$instance]="$app_without_override"
          else
            COMPOSE_INSTANCE_APP_NAMES[$instance]+=$'\n'"$app_without_override"
          fi
        fi
      done
    done
  fi

  COMPOSE_INSTANCE_NAMES=("${instance_names[@]}")
  # Touch array to satisfy shellcheck: callers rely on these globals after sourcing.
  : "${COMPOSE_INSTANCE_NAMES[@]}"

  return 0
}
