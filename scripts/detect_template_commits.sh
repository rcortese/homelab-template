#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR/lib
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
  echo "Erro: $1" >&2
  exit 1
}

# shellcheck source=lib/template_validate.sh
source "$SCRIPT_DIR/lib/template_validate.sh"

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
    [[ $# -lt 2 ]] && error "--remote requer um argumento."
    remote="$2"
    shift 2
    ;;
  --target-branch)
    [[ $# -lt 2 ]] && error "--target-branch requer um argumento."
    target_branch="$2"
    shift 2
    ;;
  --output)
    [[ $# -lt 2 ]] && error "--output requer um argumento."
    output_file="$2"
    shift 2
    ;;
  --no-fetch)
    fetch_remote=false
    shift
    ;;
  *)
    error "argumento desconhecido: $1"
    ;;
  esac
done

cd "$REPO_ROOT"

detect_remote() {
  local detected_remote=""
  if git remote | grep -Fxq "template"; then
    detected_remote="template"
  elif git remote | grep -Fxq "upstream"; then
    detected_remote="upstream"
  else
    mapfile -t remotes < <(git remote)
    if [[ ${#remotes[@]} -eq 1 ]]; then
      detected_remote="${remotes[0]}"
    fi
  fi
  printf '%s' "$detected_remote"
}

detect_target_branch() {
  local remote_name="$1"
  local branch=""
  branch="$(git remote show "$remote_name" 2>/dev/null | awk '/HEAD branch/ {print $NF; exit}')"
  if [[ -n "$branch" ]]; then
    printf '%s' "$branch"
    return 0
  fi
  if git show-ref --verify --quiet "refs/remotes/$remote_name/main"; then
    printf '%s' "main"
    return 0
  fi
  if git show-ref --verify --quiet "refs/remotes/$remote_name/master"; then
    printf '%s' "master"
    return 0
  fi
  printf '%s' ""
}

if ! template_validate_git_repository; then
  error "este diretório não é um repositório Git."
fi

if [[ -z "$remote" ]]; then
  remote="$(detect_remote)"
fi

[[ -n "$remote" ]] || error "nenhum remote detectado automaticamente. Use --remote ou defina TEMPLATE_REMOTE."

if ! template_validate_remote_exists "$remote"; then
  error "remote '$remote' não está configurado."
fi

if [[ "$fetch_remote" == true ]]; then
  git fetch --prune "$remote"
fi

if [[ -z "$target_branch" ]]; then
  target_branch="$(detect_target_branch "$remote")"
fi

[[ -n "$target_branch" ]] || error "não foi possível determinar a branch do template. Use --target-branch."

if ! template_validate_remote_branch_exists "$remote" "$target_branch"; then
  error "branch '$target_branch' não encontrado no remote '$remote'."
fi

remote_ref="$remote/$target_branch"

original_commit="$(git merge-base HEAD "$remote_ref" 2>/dev/null || true)"
[[ -n "$original_commit" ]] || error "não foi possível determinar o ancestral comum entre HEAD e $remote_ref."

first_commit="$(git rev-list --reverse --ancestry-path "${original_commit}..HEAD" | head -n 1)"
[[ -n "$first_commit" ]] || error "nenhum commit exclusivo local encontrado após $original_commit."

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
