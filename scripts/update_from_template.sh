#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Usage: scripts/update_from_template.sh [--remote <name>] [--original-commit <hash>] [--first-local-commit <hash>] [--target-branch <branch>] [--dry-run]
#
# Main arguments:
#   --remote / TEMPLATE_REMOTE               Remote name pointing to the upstream template.
#   --original-commit / ORIGINAL_COMMIT_ID   Commit hash of the template where the fork started.
#   --first-local-commit / FIRST_COMMIT_ID   Hash of the first commit unique to the derived repository.
#   --target-branch / TARGET_BRANCH          Remote branch that contains the current template version.
#
# Options:
#   --dry-run  Only shows the commands that would be executed.
#   --help     Shows this help message.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: scripts/update_from_template.sh [options]

Syncs the current repository with the upstream template using git rebase --onto.

Required parameters (can be set via environment variables or entered interactively when running in a terminal):
  --remote <name>                 or TEMPLATE_REMOTE
  --original-commit <hash>        or ORIGINAL_COMMIT_ID
  --first-local-commit <hash>     or FIRST_COMMIT_ID
  --target-branch <branch>        or TARGET_BRANCH

Additional options:
  --dry-run   Prints the commands that would be executed without applying changes.
  -h, --help  Shows this help message and exits.

Pre-conditions:
  • The working directory must be clean (no uncommitted local changes).

Examples:
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
  echo "Error: $1" >&2
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
    [[ $# -lt 2 ]] && error "--remote requires an argument."
    template_remote="$2"
    shift 2
    ;;
  --original-commit)
    [[ $# -lt 2 ]] && error "--original-commit requires an argument."
    original_commit="$2"
    shift 2
    ;;
  --first-local-commit)
    [[ $# -lt 2 ]] && error "--first-local-commit requires an argument."
    first_local_commit="$2"
    shift 2
    ;;
  --target-branch)
    [[ $# -lt 2 ]] && error "--target-branch requires an argument."
    target_branch="$2"
    shift 2
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

default_template_remote="$(template_remote_preferred_existing)"

if [[ -z "$template_remote" ]]; then
  require_interactive_input "template remote not provided. Use --remote, set TEMPLATE_REMOTE, or answer the interactive prompts."
  template_remote="$(prompt_value_with_default "Enter the template remote name" "$default_template_remote")"
fi

if [[ -z "$target_branch" ]]; then
  require_interactive_input "target branch not provided. Use --target-branch, set TARGET_BRANCH, or answer the interactive prompts."
  target_branch="$(prompt_value_with_default "Enter the template branch" "main")"
fi

if [[ -z "$original_commit" ]]; then
  require_interactive_input "original template commit hash not provided. Use --original-commit, set ORIGINAL_COMMIT_ID, or answer the interactive prompts."
  echo "Tip: use 'git merge-base <remote>/<branch> HEAD' to find the common ancestor." >&2
  original_commit="$(prompt_required_value "Enter the original template commit hash")"
fi

if [[ -z "$first_local_commit" ]]; then
  require_interactive_input "first local commit hash not provided. Use --first-local-commit, set FIRST_COMMIT_ID, or answer the interactive prompts."
  echo "Tip: use 'git log --oneline <original-hash>..HEAD' to locate the first unique commit." >&2
  first_local_commit="$(prompt_required_value "Enter the first local-only commit hash")"
fi

[[ -n "$template_remote" ]] || error "template remote not provided. Use --remote or set TEMPLATE_REMOTE."
[[ -n "$original_commit" ]] || error "original template commit hash not provided. Use --original-commit or set ORIGINAL_COMMIT_ID."
[[ -n "$first_local_commit" ]] || error "first local commit hash not provided. Use --first-local-commit or set FIRST_COMMIT_ID."
[[ -n "$target_branch" ]] || error "target branch not provided. Use --target-branch or set TARGET_BRANCH."

if ! template_validate_commit_exists "$original_commit"; then
  error "original commit $original_commit was not found."
fi

if ! template_validate_commit_exists "$first_local_commit"; then
  error "first local commit $first_local_commit was not found."
fi

if ! template_validate_remote_exists "$template_remote"; then
  error "remote '$template_remote' is not configured."
fi

if ! template_validate_is_ancestor "$original_commit" "$first_local_commit"; then
  error "commit $original_commit is not an ancestor of $first_local_commit. Check the provided identifiers."
fi

if ! template_validate_is_ancestor "$first_local_commit" HEAD; then
  current_branch_name="$(git rev-parse --abbrev-ref HEAD)"
  error "commit $first_local_commit is not part of the current branch ($current_branch_name)."
fi

if ! template_validate_remote_branch_exists "$template_remote" "$target_branch"; then
  error "branch '$target_branch' not found on remote '$template_remote'."
fi

current_branch="$(git rev-parse --abbrev-ref HEAD)"
remote_ref="$template_remote/$target_branch"

if ! template_validate_worktree_clean; then
  error "there are uncommitted local changes. Finish or discard them before continuing."
fi

if [[ "$dry_run" == true ]]; then
  template_sync_dry_run "$template_remote" "$target_branch" "$remote_ref" "$first_local_commit" "$current_branch"
  exit 0
fi

template_sync_execute "$template_remote" "$target_branch" "$remote_ref" "$first_local_commit" "$current_branch"

echo "Update completed. Review the rebased commits and run the stack tests."
