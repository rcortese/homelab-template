#!/usr/bin/env bash
# Usage: scripts/deploy_instance.sh <instancia>
#
# Automatiza um deploy guiado da instância solicitada. O fluxo monta os arquivos
# compose (base + override da instância), roda validações auxiliares e, ao final,
# dispara um health check para confirmar o estado pós `docker compose up`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=scripts/lib/deploy_args.sh
source "$SCRIPT_DIR/lib/deploy_args.sh"

# shellcheck source=scripts/lib/deploy_context.sh
source "$SCRIPT_DIR/lib/deploy_context.sh"

# shellcheck source=scripts/lib/step_runner.sh
source "$SCRIPT_DIR/lib/step_runner.sh"

if ! eval "$(parse_deploy_args "$@")"; then
  exit 1
fi

if [[ "${DEPLOY_ARGS[SHOW_HELP]}" -eq 1 ]]; then
  print_help
  exit 0
fi

INSTANCE="${DEPLOY_ARGS[INSTANCE]}"
FORCE="${DEPLOY_ARGS[FORCE]}"
DRY_RUN="${DEPLOY_ARGS[DRY_RUN]}"
RUN_STRUCTURE="${DEPLOY_ARGS[RUN_STRUCTURE]}"
RUN_VALIDATE="${DEPLOY_ARGS[RUN_VALIDATE]}"
RUN_HEALTH="${DEPLOY_ARGS[RUN_HEALTH]}"

deploy_context_eval=""
if ! deploy_context_eval="$(build_deploy_context "$REPO_ROOT" "$INSTANCE")"; then
  exit 1
fi
eval "$deploy_context_eval"

export APP_DATA_DIR="${DEPLOY_CONTEXT[APP_DATA_DIR]}"
export APP_DATA_DIR_MOUNT="${DEPLOY_CONTEXT[APP_DATA_DIR_MOUNT]}"
export COMPOSE_ENV_FILE="${DEPLOY_CONTEXT[COMPOSE_ENV_FILE]}"
export COMPOSE_ENV_FILES="${DEPLOY_CONTEXT[COMPOSE_ENV_FILES]}"
export COMPOSE_FILES="${DEPLOY_CONTEXT[COMPOSE_FILES]}"

COMPOSE_EXEC_CMD=("$REPO_ROOT/scripts/compose.sh" "$INSTANCE" -- up -d)

run_deploy_step() {
  STEP_RUNNER_DRY_RUN="$DRY_RUN" run_step "$@"
}

mapfile -t PERSISTENT_DIRS <<<"${DEPLOY_CONTEXT[PERSISTENT_DIRS]}"
DATA_UID="${DEPLOY_CONTEXT[DATA_UID]}"
DATA_GID="${DEPLOY_CONTEXT[DATA_GID]}"
APP_DATA_UID_GID="${DEPLOY_CONTEXT[APP_DATA_UID_GID]}"

compose_env_files_display="${COMPOSE_ENV_FILES//$'\n'/ }"

cat <<SUMMARY_EOF
[*] Instância: $INSTANCE
[*] COMPOSE_ENV_FILES=${compose_env_files_display}
[*] COMPOSE_ENV_FILE=${COMPOSE_ENV_FILE}
[*] COMPOSE_FILES=${COMPOSE_FILES}
SUMMARY_EOF

if [[ $RUN_STRUCTURE -eq 1 ]]; then
  if ! run_deploy_step "Validando estrutura do repositório" "$REPO_ROOT/scripts/check_structure.sh"; then
    exit $?
  fi
fi

if [[ $RUN_VALIDATE -eq 1 ]]; then
  if ! run_deploy_step "Validando manifest da instância" env "COMPOSE_INSTANCES=${INSTANCE}" "$REPO_ROOT/scripts/validate_compose.sh"; then
    exit $?
  fi
fi

if [[ $DRY_RUN -eq 1 ]]; then
  echo "[*] Dry-run habilitado. Nenhum comando foi executado."
  echo "[*] Docker Compose planejado: $(format_cmd "${COMPOSE_EXEC_CMD[@]}")"
  if [[ $RUN_HEALTH -eq 1 ]]; then
    echo "[*] Health check planejado: $(format_cmd "$REPO_ROOT/scripts/check_health.sh" "$INSTANCE")"
  else
    echo "[*] Health check automático ignorado (flag --skip-health)."
  fi
  exit 0
fi

if [[ $FORCE -ne 1 && -z "${CI:-}" ]]; then
  read -r -p "Prosseguir com o deploy? [y/N] " answer
  case "$answer" in
  [yY][eE][sS] | [yY]) ;;
  *)
    echo "[!] Execução cancelada pelo usuário." >&2
    exit 1
    ;;
  esac
fi

mkdir -p "${PERSISTENT_DIRS[@]}"

if [[ "$(id -u)" -eq 0 ]]; then
  if chown "$APP_DATA_UID_GID" "${PERSISTENT_DIRS[@]}"; then
    echo "[*] Diretórios persistentes preparados (${PERSISTENT_DIRS[*]}) com owner ${APP_DATA_UID_GID}."
  else
    echo "[!] Aviso: falha ao ajustar owner ${APP_DATA_UID_GID} em (${PERSISTENT_DIRS[*]}). Prosseguindo com owner atual." >&2
  fi
else
  echo "[*] Diretórios persistentes preparados (${PERSISTENT_DIRS[*]}). Owner desejado ${APP_DATA_UID_GID} não aplicado (permissões insuficientes)."
fi

if ! run_deploy_step "Aplicando docker compose (up -d)" "${COMPOSE_EXEC_CMD[@]}"; then
  exit $?
fi

if [[ $RUN_HEALTH -eq 1 ]]; then
  if ! run_deploy_step "Executando health check pós-deploy" "$REPO_ROOT/scripts/check_health.sh" "$INSTANCE"; then
    exit $?
  fi
else
  echo "[*] Health check automático ignorado (flag --skip-health)."
fi

echo "[*] Deploy guiado finalizado com sucesso."
