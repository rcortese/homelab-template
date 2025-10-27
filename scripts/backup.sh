#!/usr/bin/env bash
# Uso: scripts/backup.sh <instancia>
#
# Executa um backup simples pausando a stack correspondente, copiando os dados
# persistidos para o diretório `backups/` e religando a stack ao final.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ $# -lt 1 ]]; then
  cat <<'USAGE' >&2
Uso: scripts/backup.sh <instancia>

Interrompe a stack da instância informada, copia os dados persistidos para um
snapshot em backups/<instancia>-<timestamp> e sobe os serviços novamente.
USAGE
  exit 1
fi

INSTANCE="$1"

# shellcheck source=scripts/lib/deploy_context.sh
source "$SCRIPT_DIR/lib/deploy_context.sh"

# shellcheck source=scripts/lib/app_detection.sh
source "$SCRIPT_DIR/lib/app_detection.sh"

deploy_context_eval=""
if ! deploy_context_eval="$(build_deploy_context "$REPO_ROOT" "$INSTANCE")"; then
  exit 1
fi
eval "$deploy_context_eval"

export COMPOSE_ENV_FILE="${DEPLOY_CONTEXT[COMPOSE_ENV_FILE]}"
export COMPOSE_ENV_FILES="${DEPLOY_CONTEXT[COMPOSE_ENV_FILES]}"
export COMPOSE_FILES="${DEPLOY_CONTEXT[COMPOSE_FILES]}"
export APP_DATA_DIR="${DEPLOY_CONTEXT[APP_DATA_DIR]}"
export APP_DATA_DIR_MOUNT="${DEPLOY_CONTEXT[APP_DATA_DIR_MOUNT]}"

compose_cmd=("$REPO_ROOT/scripts/compose.sh" "$INSTANCE")

stack_was_stopped=0
declare -a ACTIVE_APP_SERVICES=()
declare -a KNOWN_APP_NAMES=()

if [[ -n "${DEPLOY_CONTEXT[APP_NAMES]:-}" ]]; then
  mapfile -t KNOWN_APP_NAMES < <(printf '%s\n' "${DEPLOY_CONTEXT[APP_NAMES]}")
fi

if ! app_detection__list_active_services ACTIVE_APP_SERVICES "${compose_cmd[@]}"; then
  echo "[!] Não foi possível listar serviços ativos antes do backup." >&2
  ACTIVE_APP_SERVICES=()
fi

if ((${#KNOWN_APP_NAMES[@]} > 0)) && ((${#ACTIVE_APP_SERVICES[@]} > 0)); then
  declare -a ORDERED_ACTIVE_APPS=()
  declare -A ORDERED_ACTIVE_SEEN=()

  for known_app in "${KNOWN_APP_NAMES[@]}"; do
    for detected_app in "${ACTIVE_APP_SERVICES[@]}"; do
      if [[ "$detected_app" == "$known_app" && -z "${ORDERED_ACTIVE_SEEN[$detected_app]:-}" ]]; then
        ORDERED_ACTIVE_APPS+=("$detected_app")
        ORDERED_ACTIVE_SEEN["$detected_app"]=1
        break
      fi
    done
  done

  for detected_app in "${ACTIVE_APP_SERVICES[@]}"; do
    if [[ -z "${ORDERED_ACTIVE_SEEN[$detected_app]:-}" ]]; then
      ORDERED_ACTIVE_APPS+=("$detected_app")
      ORDERED_ACTIVE_SEEN["$detected_app"]=1
    fi
  done

  ACTIVE_APP_SERVICES=("${ORDERED_ACTIVE_APPS[@]}")
fi

if ((${#ACTIVE_APP_SERVICES[@]} == 0)) && ((${#KNOWN_APP_NAMES[@]} > 0)); then
  ACTIVE_APP_SERVICES=("${KNOWN_APP_NAMES[@]}")
fi

restart_stack() {
  if [[ $stack_was_stopped -eq 1 ]]; then
    if ((${#ACTIVE_APP_SERVICES[@]} > 0)); then
      if "${compose_cmd[@]}" up -d "${ACTIVE_APP_SERVICES[@]}"; then
        echo "[*] Aplicações '${ACTIVE_APP_SERVICES[*]}' reativadas."
      else
        echo "[!] Falha ao religar as aplicações '${ACTIVE_APP_SERVICES[*]}' da instância '$INSTANCE'. Verifique manualmente." >&2
      fi
    elif "${compose_cmd[@]}" up -d; then
      echo "[*] Stack '$INSTANCE' reativada."
    else
      echo "[!] Falha ao religar a stack '$INSTANCE'. Verifique manualmente." >&2
    fi
    stack_was_stopped=0
  fi
}
trap restart_stack EXIT

echo "[*] Parando stack '$INSTANCE' antes do backup..."
if "${compose_cmd[@]}" down; then
  stack_was_stopped=1
else
  echo "[!] Falha ao parar a stack '$INSTANCE'." >&2
  exit 1
fi

app_data_dir_rel="${DEPLOY_CONTEXT[APP_DATA_DIR]}"
app_data_dir_mount="${DEPLOY_CONTEXT[APP_DATA_DIR_MOUNT]}"

echo "[*] Diretório de dados (base relativa): ${app_data_dir_rel:-<não configurado>}"

if [[ -z "$app_data_dir_mount" ]]; then
  echo "[!] Diretório de dados não identificado para a instância '$INSTANCE'." >&2
  exit 1
fi

data_src="$app_data_dir_mount"

if [[ ! -d "$data_src" ]]; then
  echo "[!] Diretório de dados '$data_src' inexistente." >&2
  exit 1
fi

if ((${#ACTIVE_APP_SERVICES[@]} > 0)); then
  echo "[*] Aplicações detectadas para religar: ${ACTIVE_APP_SERVICES[*]}"
else
  echo "[*] Nenhuma aplicação ativa identificada; religando stack completa."
fi

timestamp="$(date +%Y%m%d-%H%M%S)"
backup_dir="$REPO_ROOT/backups/${INSTANCE}-${timestamp}"
mkdir -p "$backup_dir"

echo "[*] Copiando dados de '$data_src' para '$backup_dir'..."
if ! cp -a "$data_src/." "$backup_dir/"; then
  echo "[!] Falha ao copiar os dados para '$backup_dir'." >&2
  exit 1
fi

echo "[*] Backup da instância '$INSTANCE' concluído em '$backup_dir'."

# religar stack (trap cuida em caso de erro anterior)
restart_stack
trap - EXIT

echo "[*] Processo finalizado com sucesso."
