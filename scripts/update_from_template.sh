#!/usr/bin/env bash
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

Parâmetros obrigatórios (podem ser definidos via variáveis de ambiente):
  --remote <nome>                 ou TEMPLATE_REMOTE
  --original-commit <hash>        ou ORIGINAL_COMMIT_ID
  --first-local-commit <hash>     ou FIRST_COMMIT_ID
  --target-branch <branch>        ou TARGET_BRANCH

Opções adicionais:
  --dry-run   Exibe os comandos que seriam executados sem aplicar alterações.
  -h, --help  Mostra esta ajuda e encerra a execução.

Exemplos:
  TEMPLATE_REMOTE=upstream ORIGINAL_COMMIT_ID=abc1234 FIRST_COMMIT_ID=def5678 TARGET_BRANCH=main \\
    scripts/update_from_template.sh

  scripts/update_from_template.sh \
    --remote upstream \
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

[[ -n "$template_remote" ]] || error "remote do template não informado. Use --remote ou defina TEMPLATE_REMOTE."
[[ -n "$original_commit" ]] || error "hash do commit original do template não informado. Use --original-commit ou defina ORIGINAL_COMMIT_ID."
[[ -n "$first_local_commit" ]] || error "hash do primeiro commit local não informado. Use --first-local-commit ou defina FIRST_COMMIT_ID."
[[ -n "$target_branch" ]] || error "branch alvo não informado. Use --target-branch ou defina TARGET_BRANCH."

cd "$REPO_ROOT"

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  error "este diretório não é um repositório Git."
fi

if ! git rev-parse --verify "$original_commit^{commit}" >/dev/null 2>&1; then
  error "commit original $original_commit não foi encontrado."
fi

if ! git rev-parse --verify "$first_local_commit^{commit}" >/dev/null 2>&1; then
  error "primeiro commit local $first_local_commit não foi encontrado."
fi

if ! git remote get-url "$template_remote" >/dev/null 2>&1; then
  error "remote '$template_remote' não está configurado."
fi

if ! git merge-base --is-ancestor "$original_commit" "$first_local_commit"; then
  error "o commit $original_commit não é ancestral de $first_local_commit. Verifique os identificadores informados."
fi

if ! git merge-base --is-ancestor "$first_local_commit" HEAD; then
  current_branch_name="$(git rev-parse --abbrev-ref HEAD)"
  error "o commit $first_local_commit não faz parte da branch atual ($current_branch_name)."
fi

if ! git ls-remote --exit-code "$template_remote" "$target_branch" >/dev/null 2>&1; then
  error "branch '$target_branch' não encontrado no remote '$template_remote'."
fi

current_branch="$(git rev-parse --abbrev-ref HEAD)"
remote_ref="$template_remote/$target_branch"

if [[ "$dry_run" == true ]]; then
  echo "Modo dry-run habilitado. Nenhum comando será executado."
  echo "Comandos planejados:"
  echo "  git fetch $template_remote $target_branch"
  echo "  git rebase --onto $remote_ref $original_commit $current_branch"
  exit 0
fi

echo "Buscando atualizações do template em $remote_ref..."
git fetch "$template_remote" "$target_branch"

echo "Reaplicando commits locais a partir de $first_local_commit sobre $remote_ref..."
git rebase --onto "$remote_ref" "$original_commit" "$current_branch"

echo "Atualização concluída. Revise os commits reaplicados e execute os testes da stack."
