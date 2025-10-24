#!/usr/bin/env bash
# Usage: scripts/check_health.sh [instancia]
#
# Arguments:
#   instancia (opcional): nome do arquivo compose/<instancia>.yml usado para montar os comandos.
#                         Quando informado, o script procura também env/local/<instancia>.env.
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

load_env_pairs() {
  local env_file="$1"
  shift || return 0

  if [[ ! -f "$env_file" ]]; then
    return 1
  fi

  if [[ $# -eq 0 ]]; then
    return 2
  fi

  local output=""
  if ! output="$("$SCRIPT_DIR/lib/env_loader.sh" "$env_file" "$@")"; then
    return $?
  fi

  local line key value
  while IFS= read -r line; do
    if [[ -z "$line" ]]; then
      continue
    fi
    key="${line%%=*}"
    if [[ -z "$key" ]]; then
      continue
    fi
    if [[ -n "${!key+x}" ]]; then
      continue
    fi
    value="${line#*=}"
    export "$key=$value"
  done <<< "$output"

  return 0
}

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
  -h|--help)
    print_help
    exit 0
    ;;
esac

INSTANCE_NAME="${1:-}"

if ! compose_defaults_dump="$("$SCRIPT_DIR/lib/compose_defaults.sh" "$INSTANCE_NAME" "$REPO_ROOT")"; then
  echo "[!] Não foi possível preparar variáveis padrão do docker compose." >&2
  exit 1
fi

eval "$compose_defaults_dump"

if [[ -z "${HEALTH_SERVICES:-}" && -n "${COMPOSE_ENV_FILE:-}" ]]; then
  env_file="$COMPOSE_ENV_FILE"
  if [[ "$env_file" != /* ]]; then
    env_file="$REPO_ROOT/$env_file"
  fi
  if [[ -f "$env_file" ]]; then
    load_env_pairs "$env_file" HEALTH_SERVICES SERVICE_NAME
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
    done <<< "$compose_services_output"
  fi

  unset __log_targets_seen
  unset __service
}

append_real_service_targets
unset -f append_real_service_targets

if [[ ${#LOG_TARGETS[@]} -eq 0 ]]; then
  LOG_TARGETS=(app)
fi

echo "[*] Containers:"
"${COMPOSE_CMD[@]}" ps
echo
echo "[*] Logs recentes dos serviços monitorados:"

log_success=false

for service in "${LOG_TARGETS[@]}"; do
  if "${COMPOSE_CMD[@]}" logs --tail=50 "$service"; then
    log_success=true
    break
  fi
done

if [[ "$log_success" == false ]]; then
  printf 'Failed to retrieve logs for services: %s\n' "${LOG_TARGETS[*]}" >&2
  exit 1
fi
