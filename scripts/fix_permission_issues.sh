#!/usr/bin/env bash
# Uso: scripts/fix_permission_issues.sh <instancia> [opcoes]
#
# Ajusta permissões e prepara diretórios persistentes para a instância
# informada, reaproveitando os valores configurados nos arquivos `.env`.
set -euo pipefail

print_help() {
  cat <<'USAGE'
Uso: scripts/fix_permission_issues.sh <instancia> [opcoes]

Aplica correções em permissões de diretórios persistentes associados à instância.

Opcoes disponiveis:
  --dry-run   Apenas exibe as ações planejadas sem executar comandos.
  -h, --help  Mostra esta mensagem e sai.
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=./lib/deploy_context.sh
source "$SCRIPT_DIR/lib/deploy_context.sh"

# shellcheck source=./lib/step_runner.sh
source "$SCRIPT_DIR/lib/step_runner.sh"

INSTANCE=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
  --dry-run)
    DRY_RUN=1
    ;;
  -h | --help)
    print_help
    exit 0
    ;;
  -*)
    echo "[!] Opção desconhecida: $1" >&2
    print_help >&2
    exit 1
    ;;
  *)
    if [[ -n "$INSTANCE" ]]; then
      echo "[!] Instância duplicada detectada: $1" >&2
      print_help >&2
      exit 1
    fi
    INSTANCE="$1"
    ;;
  esac
  shift
done

if [[ -z "$INSTANCE" ]]; then
  echo "[!] Nenhuma instância informada." >&2
  print_help >&2
  exit 1
fi

declare deploy_context_eval=""
if ! deploy_context_eval="$(build_deploy_context "$REPO_ROOT" "$INSTANCE")"; then
  exit 1
fi
eval "$deploy_context_eval"

persistent_dirs_raw="${DEPLOY_CONTEXT[PERSISTENT_DIRS]}"
declare -a persistent_dirs=()
if [[ -n "$persistent_dirs_raw" ]]; then
  while IFS= read -r dir; do
    [[ -z "$dir" ]] && continue
    persistent_dirs+=("$dir")
  done <<<"$persistent_dirs_raw"
fi

if [[ ${#persistent_dirs[@]} -eq 0 ]]; then
  echo "[!] Nenhum diretório persistente foi detectado para a instância '$INSTANCE'." >&2
  exit 1
fi

target_uid="${DEPLOY_CONTEXT[DATA_UID]}"
target_gid="${DEPLOY_CONTEXT[DATA_GID]}"
target_owner="${DEPLOY_CONTEXT[APP_DATA_UID_GID]}"
app_data_dir="${DEPLOY_CONTEXT[APP_DATA_DIR]}"
app_data_dir_mount="${DEPLOY_CONTEXT[APP_DATA_DIR_MOUNT]}"
compose_env_file="${DEPLOY_CONTEXT[COMPOSE_ENV_FILE]}"

cat <<SUMMARY
[*] Instância: $INSTANCE
[*] Arquivo .env: $compose_env_file
[*] Diretório de dados configurado: $app_data_dir
[*] Diretório de dados (absoluto): $app_data_dir_mount
[*] Owner desejado: ${target_owner}
[*] Diretórios persistentes:
SUMMARY
for dir in "${persistent_dirs[@]}"; do
  printf '    - %s\n' "$dir"
done

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "[*] Dry-run habilitado. Nenhuma alteração será aplicada."
  for dir in "${persistent_dirs[@]}"; do
    printf '    mkdir -p %q\n' "$dir"
  done
  if [[ "$(id -u)" -eq 0 ]]; then
    printf '    chown %s' "$target_owner"
    for dir in "${persistent_dirs[@]}"; do
      printf ' %q' "$dir"
    done
    printf '\n'
  else
    printf '    (skipped) chown %s' "$target_owner"
    for dir in "${persistent_dirs[@]}"; do
      printf ' %q' "$dir"
    done
    printf ' (requer privilégios)\n'
  fi
  exit 0
fi

for dir in "${persistent_dirs[@]}"; do
  if ! STEP_RUNNER_DRY_RUN=0 run_step "Garantindo diretório ${dir}" mkdir -p "$dir"; then
    exit $?
  fi
done

if [[ "$(id -u)" -eq 0 ]]; then
  if ! STEP_RUNNER_DRY_RUN=0 run_step "Aplicando owner ${target_owner}" chown "$target_owner" "${persistent_dirs[@]}"; then
    exit $?
  fi
else
  echo "[!] Aviso: execução sem privilégios. Owner desejado ${target_owner} não aplicado." >&2
fi

for dir in "${persistent_dirs[@]}"; do
  if [[ ! -d "$dir" ]]; then
    echo "[!] Diretório $dir não encontrado após ajustes." >&2
    exit 1
  fi

  current_uid="$(stat -c '%u' "$dir")"
  current_gid="$(stat -c '%g' "$dir")"
  if [[ "$current_uid" == "$target_uid" && "$current_gid" == "$target_gid" ]]; then
    echo "[*] Permissões alinhadas em $dir (${current_uid}:${current_gid})."
  else
    echo "[!] Aviso: $dir está com owner ${current_uid}:${current_gid} (esperado ${target_owner})." >&2
  fi

done

echo "[*] Correções de permissão concluídas para a instância '$INSTANCE'."
