#!/usr/bin/env bash

COMPOSE_DISCOVERY_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly COMPOSE_DISCOVERY_LIB_DIR
# shellcheck disable=SC1091 # dynamic path resolution via BASH_SOURCE
source "${COMPOSE_DISCOVERY_LIB_DIR}/compose_paths.sh"

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
  local env_dir_rel="env"
  local env_local_dir_rel="$env_dir_rel/local"

  BASE_COMPOSE_FILE=""
  local base_candidates=("$compose_dir_rel/base.yml" "$compose_dir_rel/base.yaml")
  local base_candidate
  for base_candidate in "${base_candidates[@]}"; do
    if [[ -f "$repo_root/$base_candidate" ]]; then
      BASE_COMPOSE_FILE="$base_candidate"
      break
    fi
  done

  declare -gA COMPOSE_INSTANCE_FILES=()
  declare -ga COMPOSE_INSTANCE_NAMES=()

  local -A known_instances=()

  shopt -s nullglob
  local -a top_level_candidates=("$repo_root/$compose_dir_rel"/docker-compose.*.yml "$repo_root/$compose_dir_rel"/docker-compose.*.yaml)
  shopt -u nullglob

  if [[ ${#top_level_candidates[@]} -gt 0 ]]; then
    mapfile -t top_level_candidates < <(printf '%s\n' "${top_level_candidates[@]}" | sort)
  fi

  local instance_file candidate_name candidate_instance
  for instance_file in "${top_level_candidates[@]}"; do
    [[ -f "$instance_file" ]] || continue
    candidate_name="${instance_file##*/}"

    case "$candidate_name" in
    docker-compose.*.yml | docker-compose.*.yaml)
      candidate_instance="${candidate_name#docker-compose.}"
      candidate_instance="${candidate_instance%.*}"
      ;;
    *)
      continue
      ;;
    esac

    if [[ -z "$candidate_instance" || "$candidate_instance" == "base" ]]; then
      continue
    fi

    known_instances[$candidate_instance]=1
    compose_discovery__append_instance_file "$candidate_instance" "$compose_dir_rel/$candidate_name"
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
    echo "[!] No instance found in $compose_dir_rel or $env_dir_rel" >&2
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

  COMPOSE_INSTANCE_NAMES=("${instance_names[@]}")
  # Touch arrays to satisfy shellcheck: callers rely on these globals after sourcing.
  : "${COMPOSE_INSTANCE_FILES[@]}"
  : "${COMPOSE_INSTANCE_NAMES[@]}"
  : "${BASE_COMPOSE_FILE}"

  return 0
}
