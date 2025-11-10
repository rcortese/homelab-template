#!/usr/bin/env bash

template_sync_dry_run() {
  local remote_name="$1"
  local target_branch="$2"
  local remote_ref="$3"
  local first_local_commit="$4"
  local current_branch="$5"

  echo "Dry-run enabled. No command will be executed."
  echo "Planned commands:"
  echo "  git fetch $remote_name $target_branch"
  echo "  git rebase --onto $remote_ref ${first_local_commit}^ $current_branch"
}

template_sync_execute() {
  local remote_name="$1"
  local target_branch="$2"
  local remote_ref="$3"
  local first_local_commit="$4"
  local current_branch="$5"

  echo "Fetching template updates from $remote_ref..."
  git fetch "$remote_name" "$target_branch"

  echo "Rebasing local commits starting at $first_local_commit (base ${first_local_commit}^) onto $remote_ref..."
  git rebase --onto "$remote_ref" "${first_local_commit}^" "$current_branch"
}
