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

# shellcheck source=./lib/deploy_context.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/deploy_context.sh"

deploy_context_eval=""
if ! deploy_context_eval="$(build_deploy_context "$REPO_ROOT" "$INSTANCE")"; then
  exit 1
fi
eval "$deploy_context_eval"

export COMPOSE_ENV_FILE="${DEPLOY_CONTEXT[COMPOSE_ENV_FILE]}"
export COMPOSE_FILES="${DEPLOY_CONTEXT[COMPOSE_FILES]}"

compose_cmd=("$REPO_ROOT/scripts/compose.sh" "$INSTANCE")

stack_was_stopped=0
declare -a ACTIVE_APP_SERVICES=()
declare -a KNOWN_APP_NAMES=()
declare -A KNOWN_APP_SET=()
declare -A ACTIVE_APP_SEEN=()

register_detected_app() {
  local candidate="$1"

  if [[ -z "$candidate" ]]; then
    return
  fi

  if ((${#KNOWN_APP_SET[@]} > 0)) && [[ -z "${KNOWN_APP_SET[$candidate]:-}" ]]; then
    return
  fi

  if [[ -n "${ACTIVE_APP_SEEN[$candidate]:-}" ]]; then
    return
  fi

  ACTIVE_APP_SEEN[$candidate]=1
  ACTIVE_APP_SERVICES+=("$candidate")
}

collect_apps_from_dir() {
  local parent_dir="$1"
  local instance_suffix=""

  if [[ -n "$INSTANCE" ]]; then
    instance_suffix="-${INSTANCE}"
  fi

  if [[ ! -d "$parent_dir" ]]; then
    return
  fi

  while IFS= read -r -d '' entry; do
    local name="${entry##*/}"
    local normalized="$name"

    if [[ -z "$normalized" ]]; then
      continue
    fi

    if [[ -n "$instance_suffix" && "$normalized" == *"$instance_suffix" ]]; then
      normalized="${normalized%"$instance_suffix"}"
    fi

    register_detected_app "$normalized"
  done < <(find "$parent_dir" -mindepth 1 -maxdepth 1 -type d -print0)
}

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

app_data_dir="${DEPLOY_CONTEXT[APP_DATA_DIR]}"
if [[ -z "$app_data_dir" ]]; then
  echo "[!] Diretório de dados não identificado para a instância '$INSTANCE'." >&2
  exit 1
fi

if [[ "$app_data_dir" != /* ]]; then
  data_src="$REPO_ROOT/$app_data_dir"
else
  data_src="$app_data_dir"
fi

if [[ ! -d "$data_src" ]]; then
  echo "[!] Diretório de dados '$data_src' inexistente." >&2
  exit 1
fi

if [[ -n "${DEPLOY_CONTEXT[APP_NAMES]:-}" ]]; then
  mapfile -t KNOWN_APP_NAMES < <(printf '%s\n' "${DEPLOY_CONTEXT[APP_NAMES]}")
  for known_app in "${KNOWN_APP_NAMES[@]}"; do
    [[ -z "$known_app" ]] && continue
    KNOWN_APP_SET["$known_app"]=1
  done
fi

collect_apps_from_dir "$data_src/apps"
collect_apps_from_dir "$data_src/data"

if ((${#KNOWN_APP_NAMES[@]} > 0)) && ((${#ACTIVE_APP_SERVICES[@]} > 0)); then
  declare -a ORDERED_ACTIVE_APPS=()
  declare -A ORDERED_ACTIVE_SEEN=()

  for known_app in "${KNOWN_APP_NAMES[@]}"; do
    if [[ -n "${ACTIVE_APP_SEEN[$known_app]:-}" ]]; then
      ORDERED_ACTIVE_APPS+=("$known_app")
      ORDERED_ACTIVE_SEEN["$known_app"]=1
    fi
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
