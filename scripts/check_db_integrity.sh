#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Script de manutenção para verificar e recuperar bancos SQLite.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ORIGINAL_PWD="${PWD:-}"
CHANGED_TO_REPO_ROOT=false

# shellcheck source=lib/app_detection.sh
source "$SCRIPT_DIR/lib/app_detection.sh"

if [[ "$ORIGINAL_PWD" != "$REPO_ROOT" ]]; then
  cd "$REPO_ROOT"
  CHANGED_TO_REPO_ROOT=true
fi

INSTANCE_NAME=""
REQUESTED_DATA_DIR="" # Utilizado pela rotina registrada em trap.
RESUME_ON_EXIT=1
SQLITE3_BIN="${SQLITE3_BIN:-sqlite3}"
SQLITE3_MODE="${SQLITE3_MODE:-container}"
SQLITE3_CONTAINER_RUNTIME="${SQLITE3_CONTAINER_RUNTIME:-docker}"
SQLITE3_CONTAINER_IMAGE="${SQLITE3_CONTAINER_IMAGE:-keinos/sqlite3:latest}"
OUTPUT_FORMAT="text"
OUTPUT_FILE=""
JSON_STDOUT_REDIRECTED=0

SQLITE3_BACKEND=""
SQLITE3_BIN_PATH=""

declare -ag COMPOSE_CMD=()
declare -ag PAUSED_SERVICES=() # Modificado quando serviços são pausados e lido no trap EXIT.
PAUSED_STACK=0

ALERTS=()
RECOVERY_BACKUP_PATH=""
RECOVERY_DETAILS=""
FIELD_SEPARATOR=$'\x1f'
declare -a DB_RESULTS=()

record_result() {
  local path="$1"
  local status="$2"
  local message="$3"
  local action="$4"
  DB_RESULTS+=("${path}${FIELD_SEPARATOR}${status}${FIELD_SEPARATOR}${message}${FIELD_SEPARATOR}${action}")
}

json_escape() {
  local raw="$1"
  raw="${raw//\\/\\\\}"
  raw="${raw//\"/\\\"}"
  raw="${raw//$'\n'/\\n}"
  raw="${raw//$'\r'/\\r}"
  raw="${raw//$'\t'/\\t}"
  printf '%s' "$raw"
}

generate_json_report() {
  local first=1
  printf '{"format":"json","overall_status":%d,"databases":[' "$overall_status"
  for entry in "${DB_RESULTS[@]}"; do
    IFS="$FIELD_SEPARATOR" read -r path status message action <<<"$entry"
    if ((first)); then
      first=0
    else
      printf ','
    fi
    printf '{"path":"%s","status":"%s","message":"%s","action":"%s"}' \
      "$(json_escape "$path")" \
      "$(json_escape "$status")" \
      "$(json_escape "$message")" \
      "$(json_escape "$action")"
  done
  printf ']'
  printf ',"alerts":['
  first=1
  for alert in "${ALERTS[@]}"; do
    if ((first)); then
      first=0
    else
      printf ','
    fi
    printf '"%s"' "$(json_escape "$alert")"
  done
  printf ']}'
}

generate_text_report() {
  local lines=()
  lines+=("Resumo da verificação de bancos SQLite:")
  for entry in "${DB_RESULTS[@]}"; do
    IFS="$FIELD_SEPARATOR" read -r path status message action <<<"$entry"
    lines+=("Banco: $path")
    lines+=("  status: $status")
    lines+=("  mensagem: $message")
    lines+=("  acao: $action")
  done
  if ((${#ALERTS[@]} > 0)); then
    lines+=("Alertas:")
    for alert in "${ALERTS[@]}"; do
      lines+=("- $alert")
    done
  fi
  printf '%s\n' "${lines[@]}"
}

print_help() {
  cat <<'USAGE'
Usage: scripts/check_db_integrity.sh instance [options]

Pauses the active services for the instance, checks the integrity of SQLite (*.db)
files inside the data directory (or custom directory), and attempts recovery when needed.

Positional arguments:
  instance               Instance name defined in the docker compose manifests.

Options:
  --data-dir <dir>       Base directory containing .db files (default: data/).
  --format {text,json}   Output format (default: text).
  --no-resume            Do not resume services after verification.
  --output <file>        Path to write the final summary.
  -h, --help             Show this help message and exit.

Relevant environment variables:
  SQLITE3_MODE               Force 'container', 'binary' or 'auto' (default: container).
  SQLITE3_CONTAINER_RUNTIME  Container runtime used (default: docker).
  SQLITE3_CONTAINER_IMAGE    sqlite3 container image (default: keinos/sqlite3:latest).
  SQLITE3_BIN                Path to a local sqlite3 binary (used in binary mode or fallback).
  DATA_DIR                   Alternative to --data-dir.

Examples:
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
    --format)
      shift
      if [[ $# -eq 0 ]]; then
        echo "Erro: --format requer um argumento (text|json)." >&2
        exit 1
      fi
      case "$1" in
      text | json)
        OUTPUT_FORMAT="$1"
        ;;
      *)
        echo "Erro: valor inválido para --format: $1" >&2
        exit 1
        ;;
      esac
      ;;
    --format=*)
      case "${1#*=}" in
      text | json)
        OUTPUT_FORMAT="${1#*=}"
        ;;
      *)
        echo "Erro: valor inválido para --format: ${1#*=}" >&2
        exit 1
        ;;
      esac
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
    --output)
      shift
      if [[ $# -eq 0 ]]; then
        echo "Erro: --output requer um caminho." >&2
        exit 1
      fi
      OUTPUT_FILE="$1"
      ;;
    --output=*)
      OUTPUT_FILE="${1#*=}"
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

if [[ "$OUTPUT_FORMAT" == "json" ]]; then
  exec 3>&1
  exec 1>&2
  JSON_STDOUT_REDIRECTED=1
fi

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
  if [[ "$OUTPUT_FORMAT" == "text" ]]; then
    echo "[*] Pausando serviços ativos: ${PAUSED_SERVICES[*]}"
  else
    echo "[*] Pausando serviços ativos: ${PAUSED_SERVICES[*]}" >&2
  fi
  if ! "${COMPOSE_CMD[@]}" pause "${PAUSED_SERVICES[@]}"; then
    echo "[!] Falha ao pausar serviços: ${PAUSED_SERVICES[*]}" >&2
  else
    # shellcheck disable=SC2034  # Lido pelo trap EXIT.
    PAUSED_STACK=1
  fi
else
  if [[ "$OUTPUT_FORMAT" == "text" ]]; then
    echo "[*] Nenhum serviço em execução encontrado para pausar."
  else
    echo "[*] Nenhum serviço em execução encontrado para pausar." >&2
  fi
fi

declare -a DB_FILES=()
while IFS= read -r -d '' file; do
  DB_FILES+=("$file")
done < <(find "$DATA_DIR" -type f -name '*.db' -print0)

if ((${#DB_FILES[@]} == 0)); then
  if [[ "$OUTPUT_FORMAT" == "text" ]]; then
    echo "[i] Nenhum arquivo .db encontrado em $DATA_DIR."
  else
    echo "[i] Nenhum arquivo .db encontrado em $DATA_DIR." >&2
  fi
  exit 0
fi

overall_status=0

for db_file in "${DB_FILES[@]}"; do
  if [[ "$OUTPUT_FORMAT" == "text" ]]; then
    echo "[*] Verificando integridade de: $db_file"
  else
    echo "[*] Verificando integridade de: $db_file" >&2
  fi
  check_output=""
  check_status=0
  if ! check_output="$(sqlite3_exec "$db_file" "PRAGMA integrity_check;" 2>&1)"; then
    check_status=$?
  fi

  if ((check_status != 0)) || [[ "$check_output" != "ok" ]]; then
    local_message="Falha de integridade: ${check_output//$'\n'/; }"
    ALERTS+=("$local_message em $db_file")
    if attempt_recovery "$db_file"; then
      action_message="Recuperação automática concluída. Backup salvo em $RECOVERY_BACKUP_PATH (${RECOVERY_DETAILS})."
      ALERTS+=("Banco '$db_file' recuperado. Backup salvo em $RECOVERY_BACKUP_PATH (${RECOVERY_DETAILS}).")
      record_result "$db_file" "recovered" "$local_message" "$action_message"
      echo "[!] $local_message" >&2
      if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo "[+] Banco recuperado, backup em $RECOVERY_BACKUP_PATH"
      else
        echo "[+] Banco recuperado, backup em $RECOVERY_BACKUP_PATH" >&2
      fi
    else
      action_message="Recuperação automática falhou: $RECOVERY_DETAILS"
      ALERTS+=("Banco '$db_file' permanece corrompido: $RECOVERY_DETAILS")
      record_result "$db_file" "failed" "$local_message" "$action_message"
      echo "[!] $local_message" >&2
      echo "[!] Falha ao recuperar $db_file: $RECOVERY_DETAILS" >&2
      overall_status=2
    fi
  else
    record_result "$db_file" "ok" "Integridade OK" "Nenhuma ação necessária"
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
      echo "[+] Integridade OK"
    else
      echo "[+] Integridade OK" >&2
    fi
  fi

done

if ((${#ALERTS[@]} > 0)); then
  echo "=== ALERTAS GERADOS ===" >&2
  for alert in "${ALERTS[@]}"; do
    echo "- $alert" >&2
  done
fi

if [[ "$OUTPUT_FORMAT" == "json" ]]; then
  json_report="$(generate_json_report)"
  if ((JSON_STDOUT_REDIRECTED == 1)); then
    exec 1>&3
    exec 3>&-
    JSON_STDOUT_REDIRECTED=0
  fi
  if [[ -n "$OUTPUT_FILE" ]]; then
    printf '%s\n' "$json_report" >"$OUTPUT_FILE"
  fi
  printf '%s\n' "$json_report"
else
  if [[ -n "$OUTPUT_FILE" ]]; then
    generate_text_report >"$OUTPUT_FILE"
  fi
fi

exit "$overall_status"
