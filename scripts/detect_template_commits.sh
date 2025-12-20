#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_OUTPUT="$REPO_ROOT/env/local/template_commits.env"

usage() {
  cat <<'USAGE'
Uso: scripts/detect_template_commits.sh [opções]

Identifica automaticamente o commit base do template (ORIGINAL_COMMIT_ID) e o
primeiro commit exclusivo do repositório derivado (FIRST_COMMIT_ID).

Opções:
  --remote <nome>         Remote que aponta para o template de origem.
  --target-branch <nome>  Branch do template usada como referência.
  --output <arquivo>      Caminho onde salvar o arquivo com os identificadores.
                          Padrão: env/local/template_commits.env
  --no-fetch              Não executa git fetch antes do cálculo.
  -h, --help              Mostra esta mensagem e sai.
USAGE
}

error() {
  echo "Error: $1" >&2
  exit 1
}

# shellcheck source=lib/template_validate.sh
source "$SCRIPT_DIR/lib/template_validate.sh"
# shellcheck source=lib/template_remote.sh
source "$SCRIPT_DIR/lib/template_remote.sh"

remote="${TEMPLATE_REMOTE:-}"
target_branch="${TARGET_BRANCH:-}"
output_file="${OUTPUT_FILE:-$DEFAULT_OUTPUT}"
fetch_remote=true

while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --remote)
    [[ $# -lt 2 ]] && error "--remote requires an argument."
    remote="$2"
    shift 2
    ;;
  --target-branch)
    [[ $# -lt 2 ]] && error "--target-branch requires an argument."
    target_branch="$2"
    shift 2
    ;;
  --output)
    [[ $# -lt 2 ]] && error "--output requires an argument."
    output_file="$2"
    shift 2
    ;;
  --no-fetch)
    fetch_remote=false
    shift
    ;;
  *)
    error "unknown argument: $1"
    ;;
  esac
done

cd "$REPO_ROOT"

if ! template_validate_git_repository; then
  error "this directory is not a Git repository."
fi

if [[ -z "$remote" ]]; then
  remote="$(template_remote_detect)"
fi

[[ -n "$remote" ]] || error "no remote detected automatically. Use --remote or set TEMPLATE_REMOTE."

if ! template_validate_remote_exists "$remote"; then
  error "remote '$remote' is not configured."
fi

if [[ "$fetch_remote" == true ]]; then
  git fetch --prune "$remote"
fi

if [[ -z "$target_branch" ]]; then
  target_branch="$(template_remote_detect_head_branch "$remote")"
fi

[[ -n "$target_branch" ]] || error "unable to determine the template branch. Use --target-branch."

if ! template_validate_remote_branch_exists "$remote" "$target_branch"; then
  error "branch '$target_branch' not found on remote '$remote'."
fi

remote_ref="$remote/$target_branch"

original_commit="$(git merge-base HEAD "$remote_ref" 2>/dev/null || true)"
[[ -n "$original_commit" ]] || error "unable to determine the common ancestor between HEAD and $remote_ref."

first_commit="$(git rev-list --reverse --ancestry-path "${original_commit}..HEAD" | head -n 1)"
[[ -n "$first_commit" ]] || error "no local-only commit found after $original_commit."

mkdir -p "$(dirname "$output_file")"
{
  echo "# Gerado por detect_template_commits.sh"
  echo "ORIGINAL_COMMIT_ID=$original_commit"
  echo "FIRST_COMMIT_ID=$first_commit"
} >"$output_file"

cat <<EOF
ORIGINAL_COMMIT_ID=$original_commit
FIRST_COMMIT_ID=$first_commit
Valores salvos em: $output_file
EOF
