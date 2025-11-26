#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Usage: scripts/fix_permission_issues.sh <instance> [options]
#
# Adjusts permissions and prepares persistent directories for the specified
# instance, reusing the values configured in the `.env` files.
set -euo pipefail

print_help() {
  cat <<'USAGE'
Usage: scripts/fix_permission_issues.sh <instance> [options]

Applies permission fixes to persistent directories associated with the instance.

Available options:
  --dry-run   Only display planned actions without executing commands.
  -h, --help  Show this message and exit.
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=lib/deploy_context.sh
source "$SCRIPT_DIR/lib/deploy_context.sh"

# shellcheck source=lib/step_runner.sh
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
    echo "[!] Unknown option: $1" >&2
    print_help >&2
    exit 1
    ;;
  *)
    if [[ -n "$INSTANCE" ]]; then
      echo "[!] Duplicate instance detected: $1" >&2
      print_help >&2
      exit 1
    fi
    INSTANCE="$1"
    ;;
  esac
  shift
done

if [[ -z "$INSTANCE" ]]; then
  echo "[!] No instance provided." >&2
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
  echo "[!] No persistent directories detected for instance '$INSTANCE'." >&2
  exit 1
fi

target_uid="${DEPLOY_CONTEXT[DATA_UID]}"
target_gid="${DEPLOY_CONTEXT[DATA_GID]}"
target_owner="${DEPLOY_CONTEXT[APP_DATA_UID_GID]}"
app_data_dir="${DEPLOY_CONTEXT[APP_DATA_DIR]}"
app_data_dir_mount="${DEPLOY_CONTEXT[APP_DATA_DIR_MOUNT]}"
compose_env_file="${DEPLOY_CONTEXT[COMPOSE_ENV_FILE]}"

cat <<SUMMARY
[*] Instance: $INSTANCE
[*] .env file: $compose_env_file
[*] Configured data directory: $app_data_dir
[*] Data directory (absolute): $app_data_dir_mount
[*] Desired owner: ${target_owner}
[*] Persistent directories:
SUMMARY
for dir in "${persistent_dirs[@]}"; do
  printf '    - %s\n' "$dir"
done

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "[*] Dry-run enabled. No changes will be applied."
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
    printf ' (requires privileges)\n'
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
