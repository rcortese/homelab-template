#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Usage: scripts/update_from_template.sh [--remote <nome>] [--original-commit <hash>] [--first-local-commit <hash>] [--target-branch <branch>] [--dry-run]
#
# Argumentos principais:
#   --remote / TEMPLATE_REMOTE               Nome do remote que aponta para o template de origem.
#   --original-commit / ORIGINAL_COMMIT_ID   Hash do commit do template onde o fork começou.
#   --first-local-commit / FIRST_COMMIT_ID   Hash do primeiro commit exclusivo do repositório derivado.
#   --target-branch / TARGET_BRANCH          Branch remoto que contém a versão atual do template.
#
# Opções:
#   --dry-run  Apenas mostra os comandos que seriam executados.
#   --help     Exibe esta mensagem de ajuda.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<'EOF'
Uso: scripts/update_from_template.sh [opções]

Sincroniza o repositório atual com o template de origem utilizando git rebase --onto.

Parâmetros obrigatórios (podem ser definidos via variáveis de ambiente ou informados interativamente quando o script é executado em um terminal):
  --remote <nome>                 ou TEMPLATE_REMOTE
  --original-commit <hash>        ou ORIGINAL_COMMIT_ID
  --first-local-commit <hash>     ou FIRST_COMMIT_ID
  --target-branch <branch>        ou TARGET_BRANCH

Opções adicionais:
  --dry-run   Exibe os comandos que seriam executados sem aplicar alterações.
  -h, --help  Mostra esta ajuda e encerra a execução.

Pré-condições:
  • O diretório de trabalho deve estar limpo (sem alterações locais pendentes de commit).

Exemplos:
  TEMPLATE_REMOTE=template ORIGINAL_COMMIT_ID=abc1234 FIRST_COMMIT_ID=def5678 TARGET_BRANCH=main \\
    scripts/update_from_template.sh

  scripts/update_from_template.sh \
    --remote template \
    --original-commit abc1234 \
    --first-local-commit def5678 \
    --target-branch main \
    --dry-run
EOF
}

error() {
  echo "Erro: $1" >&2
  echo >&2
  usage >&2
  exit 1
}

# shellcheck source=lib/template_prompts.sh
source "$SCRIPT_DIR/lib/template_prompts.sh"
# shellcheck source=lib/template_validate.sh
source "$SCRIPT_DIR/lib/template_validate.sh"
# shellcheck source=lib/template_sync.sh
source "$SCRIPT_DIR/lib/template_sync.sh"
# shellcheck source=lib/template_remote.sh
source "$SCRIPT_DIR/lib/template_remote.sh"

template_remote="${TEMPLATE_REMOTE:-}"
original_commit="${ORIGINAL_COMMIT_ID:-}"
first_local_commit="${FIRST_COMMIT_ID:-}"
target_branch="${TARGET_BRANCH:-}"
dry_run=false

while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --dry-run)
    dry_run=true
    shift
    ;;
  --remote)
    [[ $# -lt 2 ]] && error "--remote requer um argumento."
    template_remote="$2"
    shift 2
    ;;
  --original-commit)
    [[ $# -lt 2 ]] && error "--original-commit requer um argumento."
    original_commit="$2"
    shift 2
    ;;
  --first-local-commit)
    [[ $# -lt 2 ]] && error "--first-local-commit requer um argumento."
    first_local_commit="$2"
    shift 2
    ;;
  --target-branch)
    [[ $# -lt 2 ]] && error "--target-branch requer um argumento."
    target_branch="$2"
    shift 2
    ;;
  *)
    error "argumento desconhecido: $1"
    ;;
  esac
done

cd "$REPO_ROOT"

if ! template_validate_git_repository; then
  error "este diretório não é um repositório Git."
fi

default_template_remote="$(template_remote_preferred_existing)"

if [[ -z "$template_remote" ]]; then
  require_interactive_input "remote do template não informado. Use --remote, defina TEMPLATE_REMOTE ou responda às perguntas interativas."
  template_remote="$(prompt_value_with_default "Informe o nome do remote do template" "$default_template_remote")"
fi

if [[ -z "$target_branch" ]]; then
  require_interactive_input "branch alvo não informada. Use --target-branch, defina TARGET_BRANCH ou responda às perguntas interativas."
  target_branch="$(prompt_value_with_default "Informe a branch do template" "main")"
fi

if [[ -z "$original_commit" ]]; then
  require_interactive_input "hash do commit original do template não informado. Use --original-commit, defina ORIGINAL_COMMIT_ID ou responda às perguntas interativas."
  echo "Dica: utilize 'git merge-base <remote>/<branch> HEAD' para encontrar o ancestral comum." >&2
  original_commit="$(prompt_required_value "Informe o hash do commit original do template")"
fi

if [[ -z "$first_local_commit" ]]; then
  require_interactive_input "hash do primeiro commit local não informado. Use --first-local-commit, defina FIRST_COMMIT_ID ou responda às perguntas interativas."
  echo "Dica: use 'git log --oneline <hash-original>..HEAD' para localizar o primeiro commit exclusivo." >&2
  first_local_commit="$(prompt_required_value "Informe o hash do primeiro commit local exclusivo")"
fi

[[ -n "$template_remote" ]] || error "remote do template não informado. Use --remote ou defina TEMPLATE_REMOTE."
[[ -n "$original_commit" ]] || error "hash do commit original do template não informado. Use --original-commit ou defina ORIGINAL_COMMIT_ID."
[[ -n "$first_local_commit" ]] || error "hash do primeiro commit local não informado. Use --first-local-commit ou defina FIRST_COMMIT_ID."
[[ -n "$target_branch" ]] || error "branch alvo não informada. Use --target-branch ou defina TARGET_BRANCH."

if ! template_validate_commit_exists "$original_commit"; then
  error "commit original $original_commit não foi encontrado."
fi

if ! template_validate_commit_exists "$first_local_commit"; then
  error "primeiro commit local $first_local_commit não foi encontrado."
fi

if ! template_validate_remote_exists "$template_remote"; then
  error "remote '$template_remote' não está configurado."
fi

if ! template_validate_is_ancestor "$original_commit" "$first_local_commit"; then
  error "o commit $original_commit não é ancestral de $first_local_commit. Verifique os identificadores informados."
fi

if ! template_validate_is_ancestor "$first_local_commit" HEAD; then
  current_branch_name="$(git rev-parse --abbrev-ref HEAD)"
  error "o commit $first_local_commit não faz parte da branch atual ($current_branch_name)."
fi

if ! template_validate_remote_branch_exists "$template_remote" "$target_branch"; then
  error "branch '$target_branch' não encontrado no remote '$template_remote'."
fi

current_branch="$(git rev-parse --abbrev-ref HEAD)"
remote_ref="$template_remote/$target_branch"

if ! template_validate_worktree_clean; then
  error "existem alterações locais não commitadas. finalize ou descarte-as antes de continuar."
fi

if [[ "$dry_run" == true ]]; then
  template_sync_dry_run "$template_remote" "$target_branch" "$remote_ref" "$first_local_commit" "$current_branch"
  exit 0
fi

template_sync_execute "$template_remote" "$target_branch" "$remote_ref" "$first_local_commit" "$current_branch"

echo "Atualização concluída. Revise os commits reaplicados e execute os testes da stack."
