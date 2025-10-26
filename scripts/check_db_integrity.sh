#!/usr/bin/env bash
# Script de manutenção para verificar e recuperar bancos SQLite.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ORIGINAL_PWD="${PWD:-}"
CHANGED_TO_REPO_ROOT=false

# shellcheck source=./lib/app_detection.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/app_detection.sh"

if [[ "$ORIGINAL_PWD" != "$REPO_ROOT" ]]; then
  cd "$REPO_ROOT"
  CHANGED_TO_REPO_ROOT=true
fi

INSTANCE_NAME=""
REQUESTED_DATA_DIR=""
# shellcheck disable=SC2034  # Utilizado pela rotina registrada em trap.
RESUME_ON_EXIT=1
SQLITE3_BIN="${SQLITE3_BIN:-sqlite3}"
SQLITE3_MODE="${SQLITE3_MODE:-container}"
SQLITE3_CONTAINER_RUNTIME="${SQLITE3_CONTAINER_RUNTIME:-docker}"
SQLITE3_CONTAINER_IMAGE="${SQLITE3_CONTAINER_IMAGE:-keinos/sqlite3:latest}"

SQLITE3_BACKEND=""
SQLITE3_BIN_PATH=""

declare -ag COMPOSE_CMD=()
declare -ag PAUSED_SERVICES=()
# shellcheck disable=SC2034  # Modificado quando serviços são pausados e lido no trap EXIT.
PAUSED_STACK=0

ALERTS=()
RECOVERY_BACKUP_PATH=""
RECOVERY_DETAILS=""

print_help() {
  cat <<'USAGE'
Uso: scripts/check_db_integrity.sh instancia [opções]

Pausa os serviços ativos da instância, verifica a integridade dos arquivos
SQLite (*.db) dentro do diretório data (ou diretório customizado) e tenta
recuperá-los quando necessário.

Argumentos posicionais:
  instancia              Nome da instância definida nos manifests docker compose.

Opções:
  --data-dir <dir>       Diretório base contendo os arquivos .db (padrão: data/).
  --no-resume            Não retoma os serviços após a verificação.
  -h, --help             Exibe esta ajuda e sai.

Variáveis de ambiente relevantes:
  SQLITE3_MODE           Força 'container', 'binary' ou 'auto' (padrão: container).
  SQLITE3_CONTAINER_RUNTIME  Runtime de contêiner utilizado (padrão: docker).
  SQLITE3_CONTAINER_IMAGE    Imagem do contêiner sqlite3 (padrão: keinos/sqlite3:latest).
  SQLITE3_BIN            Caminho para um binário sqlite3 local (usado em modo binary ou fallback).
  DATA_DIR               Alternativa para --data-dir.

Exemplos:
  scripts/check_db_integrity.sh core
  DATA_DIR="/mnt/storage/data" scripts/check_db_integrity.sh media --no-resume
USAGE
}

resolve_sqlite_backend() {
  local resolved_bin=""

  case "$SQLITE3_MODE" in
  binary)
    if resolved_bin="$(command -v "$SQLITE3_BIN" 2>/dev/null)"; then
      SQLITE3_BACKEND="binary"
      SQLITE3_BIN_PATH="$resolved_bin"
      return 0
    fi
    echo "Erro: sqlite3 não encontrado (binário: $SQLITE3_BIN)." >&2
    exit 127
    ;;
  container)
    if command -v "$SQLITE3_CONTAINER_RUNTIME" >/dev/null 2>&1; then
      SQLITE3_BACKEND="container"
      SQLITE3_BIN_PATH=""
      return 0
    fi
    if resolved_bin="$(command -v "$SQLITE3_BIN" 2>/dev/null)"; then
      echo "[!] Runtime '$SQLITE3_CONTAINER_RUNTIME' indisponível; usando binário '$resolved_bin'." >&2
      SQLITE3_BACKEND="binary"
      SQLITE3_BIN_PATH="$resolved_bin"
      return 0
    fi
    echo "Erro: runtime '$SQLITE3_CONTAINER_RUNTIME' indisponível e sqlite3 (binário: $SQLITE3_BIN) ausente." >&2
    exit 127
    ;;
  auto | *)
    if command -v "$SQLITE3_CONTAINER_RUNTIME" >/dev/null 2>&1; then
      SQLITE3_BACKEND="container"
      SQLITE3_BIN_PATH=""
      return 0
    fi
    if resolved_bin="$(command -v "$SQLITE3_BIN" 2>/dev/null)"; then
      SQLITE3_BACKEND="binary"
      SQLITE3_BIN_PATH="$resolved_bin"
      return 0
    fi
    echo "Erro: sqlite3 não encontrado e runtime '$SQLITE3_CONTAINER_RUNTIME' indisponível." >&2
    exit 127
    ;;
  esac
}

sqlite3_exec() {
  if [[ "$SQLITE3_BACKEND" == "binary" ]]; then
    "$SQLITE3_BIN_PATH" "$@"
    return $?
  fi

  declare -a volume_args=()
  declare -A mounted_paths=()
  local arg path dir

  for arg in "$@"; do
    if [[ "$arg" == /* ]]; then
      path="$arg"
      if [[ -d "$path" ]]; then
        dir="$path"
      else
        dir="$(dirname "$path")"
      fi

      if [[ -n "$dir" && -d "$dir" && -z "${mounted_paths[$dir]:-}" ]]; then
        volume_args+=("--volume" "$dir:$dir:rw")
        mounted_paths[$dir]=1
      fi
    fi
  done

  if [[ -d "$REPO_ROOT" && -z "${mounted_paths[$REPO_ROOT]:-}" ]]; then
    volume_args+=("--volume" "$REPO_ROOT:$REPO_ROOT:rw")
    mounted_paths[$REPO_ROOT]=1
  fi

  local workdir="$REPO_ROOT"
  if [[ ! -d "$workdir" ]]; then
    workdir="$PWD"
  fi

  "$SQLITE3_CONTAINER_RUNTIME" run --rm -i \
    "${volume_args[@]}" \
    --workdir "$workdir" \
    "$SQLITE3_CONTAINER_IMAGE" \
    sqlite3 "$@"
}

trap '
  if ((PAUSED_STACK == 1 && RESUME_ON_EXIT == 1)); then
    if [[ ${#COMPOSE_CMD[@]} -gt 0 && ${#PAUSED_SERVICES[@]} -gt 0 ]]; then
      if ! "${COMPOSE_CMD[@]}" unpause "${PAUSED_SERVICES[@]}" >/dev/null 2>&1; then
        echo "[!] Falha ao retomar serviços: ${PAUSED_SERVICES[*]}" >&2
      else
        echo "[+] Serviços retomados: ${PAUSED_SERVICES[*]}" >&2
      fi
    fi
  fi

  if [[ $CHANGED_TO_REPO_ROOT == true ]]; then
    cd "$ORIGINAL_PWD" >/dev/null 2>&1 || true
  fi
' EXIT

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -h | --help)
      print_help
      exit 0
      ;;
    --data-dir)
      shift
      if [[ $# -eq 0 ]]; then
        echo "Erro: --data-dir requer um argumento." >&2
        exit 1
      fi
      REQUESTED_DATA_DIR="$1"
      ;;
    --no-resume)
      # shellcheck disable=SC2034  # Lido pelo trap EXIT.
      RESUME_ON_EXIT=0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Erro: opção desconhecida '$1'." >&2
      exit 1
      ;;
    *)
      if [[ -z "$INSTANCE_NAME" ]]; then
        INSTANCE_NAME="$1"
      else
        echo "Erro: argumento inesperado '$1'." >&2
        exit 1
      fi
      ;;
    esac
    shift || true
  done

  if [[ -z "$INSTANCE_NAME" ]]; then
    echo "Erro: informe a instância a ser analisada." >&2
    print_help >&2
    exit 1
  fi
}

attempt_recovery() {
  local db_file="$1"
  local tmp_dir

  RECOVERY_BACKUP_PATH=""
  RECOVERY_DETAILS=""

  if ! tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/db-recovery.XXXXXX")"; then
    RECOVERY_DETAILS="não foi possível criar diretório temporário"
    return 1
  fi

  local dump_file="$tmp_dir/recover.sql"
  local log_file="$tmp_dir/recover.log"
  local new_db="$tmp_dir/recovered.db"
  local timestamp backup_file

  if ! sqlite3_exec "$db_file" ".recover" >"$dump_file" 2>"$log_file"; then
    RECOVERY_DETAILS="sqlite3 .recover falhou: $(tr '\n' ' ' <"$log_file")"
    rm -rf "$tmp_dir"
    return 1
  fi

  if ! sqlite3_exec "$new_db" <"$dump_file" 2>>"$log_file"; then
    RECOVERY_DETAILS="não foi possível recriar banco: $(tr '\n' ' ' <"$log_file")"
    rm -rf "$tmp_dir"
    return 1
  fi

  timestamp="$(date +%Y%m%d%H%M%S)"
  backup_file="${db_file}.${timestamp}.bak"

  if ! cp -p "$db_file" "$backup_file"; then
    RECOVERY_DETAILS="falha ao salvar backup original em $backup_file"
    rm -rf "$tmp_dir"
    return 1
  fi

  if ! cp "$new_db" "$db_file"; then
    RECOVERY_DETAILS="falha ao substituir banco corrompido"
    cp -p "$backup_file" "$db_file" >/dev/null 2>&1 || true
    rm -rf "$tmp_dir"
    return 1
  fi

  RECOVERY_BACKUP_PATH="$backup_file"
  if [[ -s "$log_file" ]]; then
    RECOVERY_DETAILS="recuperação concluída com observações: $(tr '\n' ' ' <"$log_file")"
  else
    RECOVERY_DETAILS="recuperação concluída via sqlite3 .recover"
  fi

  rm -rf "$tmp_dir"
  return 0
}

parse_args "$@"

DATA_DIR="${REQUESTED_DATA_DIR:-${DATA_DIR:-data}}"
if [[ "$DATA_DIR" != /* ]]; then
  DATA_DIR="$REPO_ROOT/$DATA_DIR"
fi

if [[ ! -d "$DATA_DIR" ]]; then
  echo "Erro: diretório de dados não encontrado: $DATA_DIR" >&2
  exit 1
fi

resolve_sqlite_backend

if [[ "$SQLITE3_BACKEND" == "container" ]]; then
  echo "[i] Executando sqlite3 via contêiner '$SQLITE3_CONTAINER_IMAGE' (runtime: $SQLITE3_CONTAINER_RUNTIME)." >&2
fi

if ! compose_defaults_dump="$("$SCRIPT_DIR/lib/compose_defaults.sh" "$INSTANCE_NAME" ".")"; then
  echo "[!] Não foi possível preparar variáveis padrão do docker compose." >&2
  exit 1
fi

eval "$compose_defaults_dump"

if [[ ${#COMPOSE_CMD[@]} -eq 0 ]]; then
  echo "[!] Comando docker compose não configurado." >&2
  exit 1
fi

if ! command -v "${COMPOSE_CMD[0]}" >/dev/null 2>&1; then
  echo "Erro: ${COMPOSE_CMD[0]} não está disponível." >&2
  exit 127
fi

if ! app_detection__list_active_services PAUSED_SERVICES "${COMPOSE_CMD[@]}"; then
  echo "[!] Não foi possível listar serviços ativos da instância '$INSTANCE_NAME'." >&2
  PAUSED_SERVICES=()
fi

if ((${#PAUSED_SERVICES[@]} > 0)); then
  echo "[*] Pausando serviços ativos: ${PAUSED_SERVICES[*]}"
  if ! "${COMPOSE_CMD[@]}" pause "${PAUSED_SERVICES[@]}"; then
    echo "[!] Falha ao pausar serviços: ${PAUSED_SERVICES[*]}" >&2
  else
    # shellcheck disable=SC2034  # Lido pelo trap EXIT.
    PAUSED_STACK=1
  fi
else
  echo "[*] Nenhum serviço em execução encontrado para pausar."
fi

declare -a DB_FILES=()
while IFS= read -r -d '' file; do
  DB_FILES+=("$file")
done < <(find "$DATA_DIR" -type f -name '*.db' -print0)

if ((${#DB_FILES[@]} == 0)); then
  echo "[i] Nenhum arquivo .db encontrado em $DATA_DIR."
  exit 0
fi

overall_status=0

for db_file in "${DB_FILES[@]}"; do
  echo "[*] Verificando integridade de: $db_file"
  check_output=""
  check_status=0
  if ! check_output="$(sqlite3_exec "$db_file" "PRAGMA integrity_check;" 2>&1)"; then
    check_status=$?
  fi

  if ((check_status != 0)) || [[ "$check_output" != "ok" ]]; then
    local_message="Falha de integridade: ${check_output//$'\n'/; }"
    ALERTS+=("$local_message em $db_file")
    echo "[!] $local_message" >&2

    if attempt_recovery "$db_file"; then
      ALERTS+=("Banco '$db_file' recuperado. Backup salvo em $RECOVERY_BACKUP_PATH (${RECOVERY_DETAILS}).")
      echo "[+] Banco recuperado, backup em $RECOVERY_BACKUP_PATH"
    else
      ALERTS+=("Banco '$db_file' permanece corrompido: $RECOVERY_DETAILS")
      echo "[!] Falha ao recuperar $db_file: $RECOVERY_DETAILS" >&2
      overall_status=2
    fi
  else
    echo "[+] Integridade OK"
  fi

done

if ((${#ALERTS[@]} > 0)); then
  echo "=== ALERTAS GERADOS ===" >&2
  for alert in "${ALERTS[@]}"; do
    echo "- $alert" >&2
  done
fi

exit "$overall_status"
