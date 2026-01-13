#!/usr/bin/env bash
# Helpers for collecting health check log targets and logs.
set -euo pipefail

health_logs__append_real_service_targets() {
  declare -A __log_targets_seen=()
  local __service
  for __service in "${LOG_TARGETS[@]}"; do
    __log_targets_seen["$__service"]=1
  done

  local compose_services_output
  if compose_services_output="$("${COMPOSE_CMD[@]}" config --services 2>/dev/null)"; then
    local compose_service
    while IFS= read -r compose_service; do
      if [[ -z "$compose_service" ]]; then
        continue
      fi
      if [[ -n "${__log_targets_seen["$compose_service"]:-}" ]]; then
        continue
      fi
      LOG_TARGETS+=("$compose_service")
      __log_targets_seen["$compose_service"]=1
    done <<<"$compose_services_output"
  fi

  unset __log_targets_seen
  unset __service
}

health_logs__select_targets() {
  primary_targets=("${LOG_TARGETS[@]}")

  health_logs__append_real_service_targets

  auto_targets=()
  if ((${#LOG_TARGETS[@]} > ${#primary_targets[@]})); then
    auto_targets=("${LOG_TARGETS[@]:${#primary_targets[@]}}")
  fi

  ALL_LOG_TARGETS=("${primary_targets[@]}" "${auto_targets[@]}")
  LOG_TARGETS=("${primary_targets[@]}")

  if [[ ${#LOG_TARGETS[@]} -eq 0 ]]; then
    if [[ ${#auto_targets[@]} -gt 0 ]]; then
      LOG_TARGETS=("${auto_targets[@]}")
      primary_targets=("${LOG_TARGETS[@]}")
      ALL_LOG_TARGETS=("${LOG_TARGETS[@]}")
      auto_targets=()
    else
      echo "Error: no services were found for log collection." >&2
      echo "       Configure HEALTH_SERVICES or ensure the Compose manifests declare valid services." >&2
      return 1
    fi
  fi

  return 0
}

health_logs__collect_logs() {
  local service service_output
  for service in "$@"; do
    if [[ -z "$service" ]]; then
      continue
    fi
    if service_output="$("${COMPOSE_CMD[@]}" logs --tail=50 "$service" 2>&1)"; then
      SERVICE_LOGS["$service"]="$service_output"
      SERVICE_STATUSES["$service"]="ok"
      log_success=true
      if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        printf '%s\n' "$service_output"
      fi
    else
      SERVICE_LOGS["$service"]="$service_output"
      SERVICE_STATUSES["$service"]="error"
      printf '%s\n' "$service_output" >&2
      failed_services+=("$service")
    fi
  done
}
