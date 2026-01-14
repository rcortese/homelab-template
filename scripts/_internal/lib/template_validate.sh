#!/usr/bin/env bash

template_validate_git_repository() {
  git rev-parse --git-dir >/dev/null 2>&1
}

template_validate_commit_exists() {
  local commit_ref="$1"
  git rev-parse --verify "$commit_ref^{commit}" >/dev/null 2>&1
}

template_validate_remote_exists() {
  local remote_name="$1"
  git remote get-url "$remote_name" >/dev/null 2>&1
}

template_validate_is_ancestor() {
  local ancestor="$1"
  local descendant="$2"
  git merge-base --is-ancestor "$ancestor" "$descendant"
}

template_validate_remote_branch_exists() {
  local remote_name="$1"
  local branch_name="$2"
  git ls-remote --exit-code "$remote_name" "$branch_name" >/dev/null 2>&1
}

template_validate_worktree_clean() {
  [[ -z "$(git status --porcelain)" ]]
}
