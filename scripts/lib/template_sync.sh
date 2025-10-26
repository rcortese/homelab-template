#!/usr/bin/env bash

template_sync_dry_run() {
  local remote_name="$1"
  local target_branch="$2"
  local remote_ref="$3"
  local original_commit="$4"
  local current_branch="$5"

  echo "Modo dry-run habilitado. Nenhum comando será executado."
  echo "Comandos planejados:"
  echo "  git fetch $remote_name $target_branch"
  echo "  git rebase --onto $remote_ref $original_commit $current_branch"
}

template_sync_execute() {
  local remote_name="$1"
  local target_branch="$2"
  local remote_ref="$3"
  local original_commit="$4"
  local first_local_commit="$5"
  local current_branch="$6"

  echo "Buscando atualizações do template em $remote_ref..."
  git fetch "$remote_name" "$target_branch"

  echo "Reaplicando commits locais a partir de $first_local_commit sobre $remote_ref..."
  git rebase --onto "$remote_ref" "$original_commit" "$current_branch"
}
