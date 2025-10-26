#!/usr/bin/env bash
# Usage: scripts/check_health.sh [instancia]
#
# Arguments:
#   instancia (opcional): identificador usado nos manifests compose/apps/<app>/<instancia>.yml
#                         carregados a partir de compose/base.yml. Quando informado, o script
#                         procura também env/local/<instancia>.env.
# Environment:
#   COMPOSE_FILES        Lista de manifests Compose adicionais a serem aplicados (separados por espaço).
#   COMPOSE_ENV_FILE     Caminho alternativo para o arquivo de variáveis do docker compose.
#   HEALTH_SERVICES      Lista (separada por vírgula ou espaço) dos serviços para exibição de logs.
# Examples:
#   scripts/check_health.sh core
#   HEALTH_SERVICES="api worker" scripts/check_health.sh media
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ORIGINAL_PWD="${PWD:-}"
CHANGED_TO_REPO_ROOT=false

if [[ "$ORIGINAL_PWD" != "$REPO_ROOT" ]]; then
  cd "$REPO_ROOT"
  CHANGED_TO_REPO_ROOT=true
fi

REPO_ROOT="$(pwd)"

# shellcheck source=./lib/env_helpers.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/env_helpers.sh"

# shellcheck source=./lib/env_file_chain.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/env_file_chain.sh"

print_help() {
  cat <<'EOF'
Uso: scripts/check_health.sh [instancia]

Checa status básico da instância usando múltiplos compose files (via COMPOSE_FILES).

Argumentos posicionais:
  instancia   Nome da instância (ex.: core). Determina quais arquivos compose/env serão carregados.

Variáveis de ambiente relevantes:
  COMPOSE_FILES     Sobrescreve os manifests Compose usados. Separe entradas com espaço.
  COMPOSE_ENV_FILE  Define um arquivo .env alternativo para o docker compose.
  HEALTH_SERVICES   Lista (separada por vírgula/ espaço) dos serviços para exibição de logs.

Exemplos:
  scripts/check_health.sh core
  HEALTH_SERVICES="api worker" scripts/check_health.sh media
EOF
}

case "${1:-}" in
-h | --help)
  print_help
  exit 0
  ;;
esac

INSTANCE_NAME="${1:-}"

if ! compose_defaults_dump="$("$SCRIPT_DIR/lib/compose_defaults.sh" "$INSTANCE_NAME" ".")"; then
  echo "[!] Não foi possível preparar variáveis padrão do docker compose." >&2
  exit 1
fi

eval "$compose_defaults_dump"
normalize_compose_context() {
  if [[ -n "${COMPOSE_FILES:-}" ]]; then
    local sanitized="${COMPOSE_FILES//$'\n'/ }"
    local -a files_list=()
    if [[ -n "$sanitized" ]]; then
      # shellcheck disable=SC2206
      files_list=($sanitized)
    fi

    if [[ ${#files_list[@]} -gt 0 ]]; then
      local -a __filtered=()
      local __file
      for __file in "${files_list[@]}"; do
        [[ -z "$__file" ]] && continue
        __filtered+=("$__file")
      done
      COMPOSE_FILES="${__filtered[*]}"
    fi
  fi

  if [[ ${#COMPOSE_CMD[@]} -gt 0 ]]; then
    local -a __normalized_cmd=()
    local __i=0
    while ((__i < ${#COMPOSE_CMD[@]})); do
      local __token="${COMPOSE_CMD[$__i]}"
      if [[ "$__token" == "-f" ]] && ((__i + 1 < ${#COMPOSE_CMD[@]})); then
        local __value="${COMPOSE_CMD[$((__i + 1))]}"
        if [[ -n "$__value" ]]; then
          __normalized_cmd+=("$__token" "$__value")
        fi
        __i=$((__i + 2))
        continue
      fi
      __normalized_cmd+=("$__token")
      __i=$((__i + 1))
    done
    COMPOSE_CMD=("${__normalized_cmd[@]}")
  fi

  if [[ -n "${COMPOSE_EXTRA_FILES:-}" ]]; then
    local extra_entry
    local extra_input="${COMPOSE_EXTRA_FILES//$'\n'/ }"
    extra_input="${extra_input//,/ }"
    for extra_entry in $extra_input; do
      [[ -z "$extra_entry" ]] && continue
      local resolved_extra="$extra_entry"
      if [[ "$resolved_extra" != /* ]]; then
        resolved_extra="$REPO_ROOT/$resolved_extra"
      fi

      local already_present=0
      local idx=0
      while ((idx < ${#COMPOSE_CMD[@]})); do
        if [[ "${COMPOSE_CMD[$idx]}" == "-f" ]]; then
          if ((idx + 1 < ${#COMPOSE_CMD[@]})); then
            if [[ "${COMPOSE_CMD[$((idx + 1))]}" == "$resolved_extra" ]]; then
              already_present=1
              break
            fi
          fi
          idx=$((idx + 2))
          continue
        fi
        idx=$((idx + 1))
      done

      if ((already_present == 0)); then
        COMPOSE_CMD+=(-f "$resolved_extra")
      fi
    done
  fi
}

normalize_compose_context

if ! command -v "${COMPOSE_CMD[0]}" >/dev/null 2>&1; then
  echo "Error: ${COMPOSE_CMD[0]} is not available. Set DOCKER_COMPOSE_BIN if needed." >&2
  exit 127
fi

if [[ -z "${HEALTH_SERVICES:-}" ]]; then
  declare -a health_env_files=()
  if [[ -n "${COMPOSE_ENV_FILES:-}" ]]; then
    env_file_chain__parse_list "${COMPOSE_ENV_FILES}" health_env_files
  elif [[ -n "${COMPOSE_ENV_FILE:-}" ]]; then
    health_env_files=("$COMPOSE_ENV_FILE")
  fi

  if [[ ${#health_env_files[@]} -gt 0 ]]; then
    declare -A __health_env_values=()
    for env_candidate in "${health_env_files[@]}"; do
      env_abs="$env_candidate"
      if [[ "$env_abs" != /* ]]; then
        env_abs="$REPO_ROOT/$env_abs"
      fi
      if [[ ! -f "$env_abs" ]]; then
        continue
      fi
      if env_output="$("$SCRIPT_DIR/lib/env_loader.sh" "$env_abs" COMPOSE_EXTRA_FILES HEALTH_SERVICES SERVICE_NAME 2>/dev/null)"; then
        while IFS='=' read -r line; do
          [[ -z "$line" ]] && continue
          key="${line%%=*}"
          value="${line#*=}"
          __health_env_values[$key]="$value"
        done <<<"$env_output"
      fi
    done

    defaults_refreshed=0
    if [[ -n "${__health_env_values[COMPOSE_EXTRA_FILES]+x}" ]]; then
      COMPOSE_EXTRA_FILES="${__health_env_values[COMPOSE_EXTRA_FILES]}"
      defaults_refreshed=1
    fi
    if [[ -n "${__health_env_values[HEALTH_SERVICES]+x}" ]]; then
      HEALTH_SERVICES="${__health_env_values[HEALTH_SERVICES]}"
      defaults_refreshed=1
    fi
    if [[ -n "${__health_env_values[SERVICE_NAME]+x}" ]]; then
      SERVICE_NAME="${__health_env_values[SERVICE_NAME]}"
      defaults_refreshed=1
    fi

    if ((defaults_refreshed == 1)); then
      if ! compose_defaults_dump="$("$SCRIPT_DIR/lib/compose_defaults.sh" "$INSTANCE_NAME" ".")"; then
        echo "[!] Não foi possível preparar variáveis padrão do docker compose." >&2
        exit 1
      fi

      eval "$compose_defaults_dump"
      normalize_compose_context
    fi
    unset __health_env_values
  fi
fi

parse_services() {
  local raw="$1"
  local tokens=()
  local item
  if [[ -z "$raw" ]]; then
    return
  fi
  raw="${raw//,/ }"
  for item in $raw; do
    if [[ -n "$item" ]]; then
      tokens+=("$item")
    fi
  done
  printf '%s\n' "${tokens[@]}"
}

mapfile -t LOG_TARGETS < <(parse_services "${HEALTH_SERVICES:-${SERVICE_NAME:-}}") || true
primary_targets=("${LOG_TARGETS[@]}")

append_real_service_targets() {
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

append_real_service_targets
unset -f append_real_service_targets

auto_targets=()
if ((${#LOG_TARGETS[@]} > ${#primary_targets[@]})); then
  auto_targets=("${LOG_TARGETS[@]:${#primary_targets[@]}}")
fi
ALL_LOG_TARGETS=("${primary_targets[@]}" "${auto_targets[@]}")
LOG_TARGETS=("${primary_targets[@]}")

if [[ ${#LOG_TARGETS[@]} -eq 0 ]]; then
  if [[ ${#auto_targets[@]} -gt 0 ]]; then
    LOG_TARGETS=("${auto_targets[@]}")
    auto_targets=()
  else
    LOG_TARGETS=(app)
  fi
fi

if [[ -n "$INSTANCE_NAME" && "$CHANGED_TO_REPO_ROOT" == false ]]; then
  auto_targets=()
  ALL_LOG_TARGETS=("${LOG_TARGETS[@]}")
fi

echo "[*] Containers:"
"${COMPOSE_CMD[@]}" ps
echo
echo "[*] Logs recentes dos serviços monitorados:"

log_success=false
failed_services=()

for service in "${LOG_TARGETS[@]}"; do
  if "${COMPOSE_CMD[@]}" logs --tail=50 "$service"; then
    log_success=true
  else
    failed_services+=("$service")
  fi
done

if [[ ${#auto_targets[@]} -gt 0 ]]; then
  for service in "${auto_targets[@]}"; do
    if "${COMPOSE_CMD[@]}" logs --tail=50 "$service"; then
      log_success=true
    else
      failed_services+=("$service")
    fi
  done
fi

if [[ "$log_success" == false ]]; then
  printf 'Failed to retrieve logs for services: %s\n' "${ALL_LOG_TARGETS[*]}" >&2
  exit 1
fi

if [[ ${#failed_services[@]} -gt 0 ]]; then
  printf 'Warning: Failed to retrieve logs for services: %s\n' "${failed_services[*]}" >&2
fi
