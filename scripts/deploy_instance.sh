#!/usr/bin/env bash
# Usage: scripts/deploy_instance.sh <instancia>
#
# Automatiza um deploy guiado da instância solicitada. O fluxo monta os arquivos
# compose (base + override da instância), roda validações auxiliares e, ao final,
# dispara um health check para confirmar o estado pós `docker compose up`.
set -euo pipefail

print_help() {
  cat <<'USAGE'
Uso: scripts/deploy_instance.sh <instancia> [flags]

Realiza um deploy guiado da instância (core/media), carregando automaticamente
os arquivos compose necessários (base + override da instância) e executando
validações auxiliares.

Argumentos posicionais:
  instancia       Nome da instância (ex.: core, media).

Flags:
  --dry-run       Apenas exibe os comandos que seriam executados.
  --force         Pula confirmações interativas (útil localmente ou em CI).
  --skip-structure  Não executa scripts/check_structure.sh antes do deploy.
  --skip-validate   Não executa scripts/validate_compose.sh antes do deploy.
  --skip-health     Não executa scripts/check_health.sh após o deploy.
  -h, --help      Mostra esta ajuda e sai.

Variáveis de ambiente relevantes:
  CI              Quando definida, assume modo não interativo (equivalente a --force).
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=lib/env_helpers.sh
source "$SCRIPT_DIR/lib/env_helpers.sh"

if ! compose_metadata="$("$SCRIPT_DIR/lib/compose_instances.sh" "$REPO_ROOT")"; then
  echo "[!] Não foi possível carregar metadados das instâncias." >&2
  exit 1
fi

eval "$compose_metadata"

INSTANCE=""
FORCE=0
DRY_RUN=0
RUN_STRUCTURE=1
RUN_VALIDATE=1
RUN_HEALTH=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      print_help
      exit 0
      ;;
    --force)
      FORCE=1
      shift
      continue
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      continue
      ;;
    --skip-structure)
      RUN_STRUCTURE=0
      shift
      continue
      ;;
    --skip-validate)
      RUN_VALIDATE=0
      shift
      continue
      ;;
    --skip-health)
      RUN_HEALTH=0
      shift
      continue
      ;;
    -*)
      echo "[!] Flag desconhecida: $1" >&2
      echo >&2
      print_help >&2
      exit 1
      ;;
    *)
      if [[ -z "$INSTANCE" ]]; then
        INSTANCE="$1"
      else
        echo "[!] Parâmetro inesperado: $1" >&2
        echo >&2
        print_help >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$INSTANCE" ]]; then
  echo "[!] Instância não informada." >&2
  echo >&2
  print_help >&2
  exit 1
fi

if [[ -z "${COMPOSE_INSTANCE_FILES[$INSTANCE]:-}" ]]; then
  candidate_rel="compose/${INSTANCE}.yml"
  candidate_abs="$REPO_ROOT/$candidate_rel"
  if [[ ! -f "$candidate_abs" ]]; then
    echo "[!] Arquivo esperado ${candidate_rel} não encontrado para instância '$INSTANCE'." >&2
  else
    echo "[!] Instância '$INSTANCE' inválida." >&2
  fi
  echo "    Disponíveis: ${COMPOSE_INSTANCE_NAMES[*]}" >&2
  exit 1
fi

LOCAL_ENV_FILE="${COMPOSE_INSTANCE_ENV_LOCAL[$INSTANCE]:-}"
TEMPLATE_FILE="${COMPOSE_INSTANCE_ENV_TEMPLATES[$INSTANCE]:-}"

if [[ -z "$LOCAL_ENV_FILE" ]]; then
  template_display="${TEMPLATE_FILE:-env/${INSTANCE}.example.env}"

  if [[ -n "$TEMPLATE_FILE" && -f "$REPO_ROOT/$TEMPLATE_FILE" ]]; then
    echo "[!] Arquivo env/local/${INSTANCE}.env não encontrado." >&2
    echo "    Copie o template padrão antes de continuar:" >&2
    echo "    mkdir -p env/local" >&2
    echo "    cp ${TEMPLATE_FILE} env/local/${INSTANCE}.env" >&2
  else
    echo "[!] Nenhum arquivo .env foi encontrado para a instância '$INSTANCE'." >&2
    echo "    Esperado: env/local/${INSTANCE}.env ou ${template_display}" >&2
  fi
  exit 1
fi

ENV_FILE="$LOCAL_ENV_FILE"
ENV_FILE_ABS="$REPO_ROOT/$ENV_FILE"

if [[ ! -f "$ENV_FILE_ABS" ]]; then
  echo "[!] Arquivo ${ENV_FILE} não encontrado." >&2
  if [[ -n "$TEMPLATE_FILE" && -f "$REPO_ROOT/$TEMPLATE_FILE" ]]; then
    echo "    Copie o template padrão antes de continuar:" >&2
    echo "    cp ${TEMPLATE_FILE} ${ENV_FILE}" >&2
  elif [[ -n "$TEMPLATE_FILE" ]]; then
    echo "    Template correspondente (${TEMPLATE_FILE}) também não foi localizado." >&2
  fi
  exit 1
fi

if [[ -n "$ENV_FILE_ABS" ]]; then
  load_env_pairs "$ENV_FILE_ABS" \
    COMPOSE_EXTRA_FILES \
    APP_DATA_DIR \
    APP_DATA_UID \
    APP_DATA_GID
fi

extra_compose_files=()
if [[ -n "${COMPOSE_EXTRA_FILES:-}" ]]; then
  IFS=$' \t\n' read -r -a extra_compose_files <<<"${COMPOSE_EXTRA_FILES//,/ }"
fi

COMPOSE_FILES_LIST=("$BASE_COMPOSE_FILE" "${COMPOSE_INSTANCE_FILES[$INSTANCE]}")

if [[ ${#extra_compose_files[@]} -gt 0 ]]; then
  COMPOSE_FILES_LIST+=("${extra_compose_files[@]}")
fi

COMPOSE_ENV_FILE="$ENV_FILE"
COMPOSE_FILES="${COMPOSE_FILES_LIST[*]}"

export COMPOSE_ENV_FILE
export COMPOSE_FILES

COMPOSE_EXEC_CMD=("$REPO_ROOT/scripts/compose.sh" "$INSTANCE" -- up -d)

cat <<EOF
[*] Instância: $INSTANCE
[*] COMPOSE_ENV_FILE=${COMPOSE_ENV_FILE}
[*] COMPOSE_FILES=${COMPOSE_FILES}
EOF

format_cmd() {
  local output=""
  for arg in "$@"; do
    output+="$(printf '%q ' "$arg")"
  done
  printf '%s' "${output% }"
}

run_step() {
  local description="$1"
  shift
  local cmd_display
  local cmd_exec=()

  if [[ $# -eq 0 ]]; then
    echo "[!] Nenhum comando fornecido para run_step." >&2
    exit 1
  fi

  if [[ $# -eq 1 ]]; then
    cmd_display="$1"
    cmd_exec=(bash -lc "$1")
  else
    cmd_exec=("$@")
    cmd_display="$(format_cmd "${cmd_exec[@]}")"
  fi

  echo "[*] ${description}"
  echo "    ${cmd_display}"

  if [[ $DRY_RUN -eq 1 ]]; then
    return 0
  fi

  if ! "${cmd_exec[@]}"; then
    local status=$?
    echo "[!] Falha ao executar passo: ${description}" >&2
    exit $status
  fi
}

if [[ $RUN_STRUCTURE -eq 1 ]]; then
  run_step "Validando estrutura do repositório" "$REPO_ROOT/scripts/check_structure.sh"
fi

if [[ $RUN_VALIDATE -eq 1 ]]; then
  run_step "Validando manifest da instância" env "COMPOSE_INSTANCES=${INSTANCE}" "$REPO_ROOT/scripts/validate_compose.sh"
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

DATA_DIR_NAME="${APP_DATA_DIR:-data}"
DATA_UID="${APP_DATA_UID:-1000}"
DATA_GID="${APP_DATA_GID:-1000}"

PERSISTENT_DIRS=("$REPO_ROOT/$DATA_DIR_NAME" "$REPO_ROOT/backups")
APP_DATA_UID_GID="${DATA_UID}:${DATA_GID}"
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

run_step "Aplicando docker compose (up -d)" "${COMPOSE_EXEC_CMD[@]}"

if [[ $RUN_HEALTH -eq 1 ]]; then
  run_step "Executando health check pós-deploy" "$REPO_ROOT/scripts/check_health.sh" "$INSTANCE"
else
  echo "[*] Health check automático ignorado (flag --skip-health)."
fi

echo "[*] Deploy guiado finalizado com sucesso."
