#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Usage: scripts/fix_permission_issues.sh <instance> [options]
#
# Adjusts permissions and prepares persistent directories for the selected
# instance, reusing the values configured in the `.env` files.
set -euo pipefail

print_help() {
  cat <<'USAGE'
Usage: scripts/fix_permission_issues.sh <instance> [options]

Applies permission fixes for persistent directories tied to the instance.

Available options:
  --dry-run          Shows planned actions without running commands.
  --chmod <mode>     Applies chmod to persistent directories (e.g., 775).
  --chmod-recursive  Applies chmod recursively.
  -h, --help         Shows this message and exits.
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=_internal/lib/deploy_context.sh
source "$SCRIPT_DIR/_internal/lib/deploy_context.sh"

# shellcheck source=_internal/lib/step_runner.sh
source "$SCRIPT_DIR/_internal/lib/step_runner.sh"

INSTANCE=""
DRY_RUN=0
CHMOD_MODE=""
CHMOD_RECURSIVE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
  --dry-run)
    DRY_RUN=1
    ;;
  --chmod)
    shift
    if [[ -z "${1:-}" ]]; then
      echo "[!] --chmod requires a mode (example: 775)." >&2
      print_help >&2
      exit 1
    fi
    CHMOD_MODE="$1"
    ;;
  --chmod=*)
    CHMOD_MODE="${1#*=}"
    if [[ -z "$CHMOD_MODE" ]]; then
      echo "[!] --chmod requires a mode (example: 775)." >&2
      print_help >&2
      exit 1
    fi
    ;;
  --chmod-recursive)
    CHMOD_RECURSIVE=1
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
app_data_dir="${DEPLOY_CONTEXT[APP_DATA_REL]}"
app_data_dir_mount="${DEPLOY_CONTEXT[APP_DATA_PATH]}"
compose_env_files="${DEPLOY_CONTEXT[COMPOSE_ENV_FILES]}"

cat <<SUMMARY
[*] Instance: $INSTANCE
[*] .env chain: ${compose_env_files//$'\n'/ }
[*] Configured data directory: $app_data_dir
[*] Data directory (absolute): $app_data_dir_mount
[*] Desired owner: ${target_owner}
[*] Persistent directories (including bind mounts):
SUMMARY
for dir in "${persistent_dirs[@]}"; do
  printf '    - %s\n' "$dir"
done
if [[ -n "$CHMOD_MODE" ]]; then
  if [[ "$CHMOD_RECURSIVE" -eq 1 ]]; then
    echo "[*] Requested chmod: ${CHMOD_MODE} (recursive)."
  else
    echo "[*] Requested chmod: ${CHMOD_MODE}."
  fi
fi

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
  if [[ -n "$CHMOD_MODE" ]]; then
    if [[ "$CHMOD_RECURSIVE" -eq 1 ]]; then
      printf '    chmod -R %q' "$CHMOD_MODE"
    else
      printf '    chmod %q' "$CHMOD_MODE"
    fi
    for dir in "${persistent_dirs[@]}"; do
      printf ' %q' "$dir"
    done
    printf '\n'
  fi
  exit 0
fi

for dir in "${persistent_dirs[@]}"; do
  if ! STEP_RUNNER_DRY_RUN=0 run_step "Ensuring directory ${dir}" mkdir -p "$dir"; then
    exit $?
  fi
done

if [[ "$(id -u)" -eq 0 ]]; then
  if ! STEP_RUNNER_DRY_RUN=0 run_step "Applying owner ${target_owner}" chown "$target_owner" "${persistent_dirs[@]}"; then
    exit $?
  fi
else
  echo "[!] Warning: running without privileges. Desired owner ${target_owner} not applied." >&2
fi

if [[ -n "$CHMOD_MODE" ]]; then
  chmod_args=()
  if [[ "$CHMOD_RECURSIVE" -eq 1 ]]; then
    chmod_args+=("-R")
  fi
  chmod_args+=("$CHMOD_MODE")
  for dir in "${persistent_dirs[@]}"; do
    if ! chmod "${chmod_args[@]}" "$dir"; then
      if [[ "$(id -u)" -ne 0 ]]; then
        echo "[!] Warning: chmod ${CHMOD_MODE} failed on ${dir}; check ownership or run as root." >&2
      else
        echo "[!] Warning: chmod ${CHMOD_MODE} failed on ${dir}." >&2
      fi
    fi
  done
fi

for dir in "${persistent_dirs[@]}"; do
  if [[ ! -d "$dir" ]]; then
    echo "[!] Directory $dir not found after adjustments." >&2
    exit 1
  fi

  current_uid="$(stat -c '%u' "$dir")"
  current_gid="$(stat -c '%g' "$dir")"
  if [[ "$current_uid" == "$target_uid" && "$current_gid" == "$target_gid" ]]; then
    echo "[*] Permissions aligned on $dir (${current_uid}:${current_gid})."
  else
    echo "[!] Warning: $dir is owned by ${current_uid}:${current_gid} (expected ${target_owner})." >&2
  fi

done

echo "[*] Permission fixes completed for instance '$INSTANCE'."
