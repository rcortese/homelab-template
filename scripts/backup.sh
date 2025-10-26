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
restart_stack() {
  if [[ $stack_was_stopped -eq 1 ]]; then
    if "${compose_cmd[@]}" up -d; then
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
