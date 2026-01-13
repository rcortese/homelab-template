#!/usr/bin/env bash

# template_remote_default_name returns the canonical remote name used for the
# upstream template repository when no explicit value is provided.
template_remote_default_name() {
  printf '%s' "${TEMPLATE_REMOTE_NAME_DEFAULT:-template}"
}

# template_remote_exists checks whether a Git remote with the provided name is
# configured for the current repository.
template_remote_exists() {
  local remote_name="$1"
  git remote | grep -Fxq "$remote_name"
}

# template_remote_preferred_existing returns the preferred remote name that
# should be suggested to the user when prompting for the template remote. It
# favors a remote named after the default template remote and falls back to
# "upstream" when available before returning the canonical default name.
template_remote_preferred_existing() {
  local default_remote
  default_remote="$(template_remote_default_name)"

  if template_remote_exists "$default_remote"; then
    printf '%s' "$default_remote"
    return 0
  fi

  if template_remote_exists "upstream"; then
    printf '%s' "upstream"
    return 0
  fi

  printf '%s' "$default_remote"
}

# template_remote_detect chooses the most likely remote that represents the
# upstream template. It reuses the preferred existing remote when present, then
# falls back to the only configured remote if the repository only has a single
# remote defined. As a last resort, it returns the canonical default name.
template_remote_detect() {
  local preferred_remote
  preferred_remote="$(template_remote_preferred_existing)"

  if template_remote_exists "$preferred_remote"; then
    printf '%s' "$preferred_remote"
    return 0
  fi

  mapfile -t remotes < <(git remote)
  if [[ ${#remotes[@]} -eq 1 ]]; then
    printf '%s' "${remotes[0]}"
    return 0
  fi

  printf '%s' "$preferred_remote"
}

# template_remote_detect_head_branch attempts to determine the default branch
# advertised by the provided remote. It first inspects the symbolic ref exposed
# by `git remote show` and then falls back to the conventional `main` and
# `master` branches if the remote does not advertise a HEAD reference.
template_remote_detect_head_branch() {
  local remote_name="$1"
  local branch

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
