#!/usr/bin/env bash
# Usage: scripts/bootstrap_instance.sh <application> <instance> [options]
#
# Initializes the default structure for a new application/instance in the template,
# generating Compose manifests, variable template, and optional documentation.
set -euo pipefail

print_usage() {
  cat <<'USAGE'
Usage: scripts/bootstrap_instance.sh <application> <instance> [options]

Generates base files for a new application/instance following the template standard.

Positional arguments:
  application   Application name (lowercase letters, numbers, hyphens, or underscores).
  instance      Instance name (lowercase letters, numbers, hyphens, or underscores).

Options:
  --base-dir <dir>   Repository root directory to use (default: script directory/..).
  --with-docs        Also creates docs/apps/<application>.md and adds the link to docs/README.md.
  --override-only    Skips creating compose/apps/<application>/base.yml (override-only mode).
  -h, --help         Show this message and exit.
USAGE
}

error() {
  printf '%s\n' "$1" >&2
}

require_valid_name() {
  local value="$1"
  local label="$2"
  if [[ ! $value =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
    error "Error: $label must start with a lowercase letter or number and contain only lowercase letters, numbers, hyphens, or underscores."
    exit 1
  fi
}

uppercase_token() {
  local value="$1"
  value="${value//-/_}"
  value="${value//./_}"
  value="${value// /_}"
  value="${value//__/_}"
  printf '%s' "${value^^}"
}

title_case() {
  local value="$1"
  value="${value//_/ }"
  value="${value//-/ }"
  local word=""
  local result=""
  for word in $value; do
    if [[ -n $result ]]; then
      result+=" "
    fi
    if [[ -n $word ]]; then
      result+="${word^}"
    fi
  done
  if [[ -z $result ]]; then
    result="$1"
  fi
  printf '%s' "$result"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_NAME=""
INSTANCE_NAME=""
BASE_DIR="$DEFAULT_BASE_DIR"
WITH_DOCS=0
OVERRIDE_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    print_usage
    exit 0
    ;;
  --base-dir)
    shift
    if [[ $# -eq 0 ]]; then
      error "Error: --base-dir requires an argument."
      exit 1
    fi
    if ! BASE_DIR="$(cd "$1" && pwd)"; then
      error "Error: invalid base directory: $1"
      exit 1
    fi
    ;;
  --with-docs)
    WITH_DOCS=1
    ;;
  --override-only)
    OVERRIDE_ONLY=1
    ;;
  --*)
    error "Error: unknown option: $1"
    print_usage >&2
    exit 1
    ;;
  *)
    if [[ -z $APP_NAME ]]; then
      APP_NAME="$1"
    elif [[ -z $INSTANCE_NAME ]]; then
      INSTANCE_NAME="$1"
    else
      error "Error: unrecognized extra arguments: $1"
      print_usage >&2
      exit 1
    fi
    ;;
  esac
  shift || true
done

if [[ -z $APP_NAME || -z $INSTANCE_NAME ]]; then
  error "Error: <application> and <instance> are required."
  print_usage >&2
  exit 1
fi

require_valid_name "$APP_NAME" "Application name"
require_valid_name "$INSTANCE_NAME" "Instance name"

APP_UPPER="$(uppercase_token "$APP_NAME")"
INSTANCE_UPPER="$(uppercase_token "$INSTANCE_NAME")"
APP_TITLE="$(title_case "$APP_NAME")"
PORT_VAR="${APP_UPPER}_${INSTANCE_UPPER}_PORT"

compose_app_dir="$BASE_DIR/compose/apps/$APP_NAME"
compose_base_file="$compose_app_dir/base.yml"
compose_instance_file="$compose_app_dir/$INSTANCE_NAME.yml"
env_example_file="$BASE_DIR/env/${INSTANCE_NAME}.example.env"
create_env_example=1
if [[ -e $env_example_file ]]; then
  create_env_example=0
fi
docs_apps_dir="$BASE_DIR/docs/apps"
app_doc_file="$docs_apps_dir/$APP_NAME.md"
docs_readme_file="$BASE_DIR/docs/README.md"

SKIP_BASE=0
if [[ $OVERRIDE_ONLY -eq 1 ]]; then
  SKIP_BASE=1
elif [[ -d $compose_app_dir && ! -e $compose_base_file ]]; then
  SKIP_BASE=1
fi

conflicts=()
if [[ $SKIP_BASE -eq 0 ]]; then
  targets=("$compose_base_file" "$compose_instance_file")
else
  targets=("$compose_instance_file")
fi

for target in "${targets[@]}"; do
  if [[ -e $target ]]; then
    conflicts+=("$target")
  fi
done

if [[ $WITH_DOCS -eq 1 ]]; then
  if [[ -e $app_doc_file ]]; then
    conflicts+=("$app_doc_file")
  fi
fi

if [[ ${#conflicts[@]} -gt 0 ]]; then
  error "Error: the following files already exist and block instance creation:"
  for path in "${conflicts[@]}"; do
    error "  - $path"
  done
  error "Aborting to avoid overwrites."
  exit 1
fi

mkdir -p "$compose_app_dir"
mkdir -p "$BASE_DIR/env"
if [[ $WITH_DOCS -eq 1 ]]; then
  mkdir -p "$docs_apps_dir"
fi

templates_root="$SCRIPT_DIR/templates/bootstrap"

render_template() {
  local template_name="$1"
  local destination="$2"
  local template_path="$templates_root/$template_name"
  if [[ ! -f $template_path ]]; then
    error "Error: template not found: $template_path"
    exit 1
  fi
  local content
  content="$(<"$template_path")"
  content="${content//\{\{APP\}\}/$APP_NAME}"
  content="${content//\{\{INSTANCE\}\}/$INSTANCE_NAME}"
  content="${content//\{\{APP_UPPER\}\}/$APP_UPPER}"
  content="${content//\{\{INSTANCE_UPPER\}\}/$INSTANCE_UPPER}"
  content="${content//\{\{PORT_VAR\}\}/$PORT_VAR}"
  content="${content//\{\{APP_TITLE\}\}/$APP_TITLE}"
  printf '%s' "$content" >"$destination"
}

if [[ $SKIP_BASE -eq 0 ]]; then
  render_template "compose-base.yml.tpl" "$compose_base_file"
fi
render_template "compose-instance.yml.tpl" "$compose_instance_file"
if [[ $create_env_example -eq 1 ]]; then
  render_template "env-example.tpl" "$env_example_file"
else
  echo "[*] env/${INSTANCE_NAME}.example.env already exists; keeping unchanged."
fi

if [[ $SKIP_BASE -eq 1 ]]; then
  if [[ $OVERRIDE_ONLY -eq 1 ]]; then
    echo "[*] Override-only mode: compose/apps/${APP_NAME}/base.yml will not be created."
  else
    echo "[*] Existing directory without base.yml detected; skipping creation of compose/apps/${APP_NAME}/base.yml."
  fi
fi

if [[ $WITH_DOCS -eq 1 ]]; then
  render_template "doc-app.md.tpl" "$app_doc_file"
  if [[ -f $docs_readme_file ]]; then
    doc_link="- [${APP_TITLE}](./apps/${APP_NAME}.md)"
    if ! grep -Fq "$doc_link" "$docs_readme_file"; then
      if grep -q '^## Applications' "$docs_readme_file"; then
        printf '\n%s\n' "$doc_link" >>"$docs_readme_file"
      else
        cat <<'DOCS_SECTION' >>"$docs_readme_file"

## Applications

DOCS_SECTION
        printf '%s\n' "$doc_link" >>"$docs_readme_file"
      fi
    fi
  fi
fi

echo "[*] Application: $APP_NAME"
echo "[*] Instance: $INSTANCE_NAME"
echo "[*] Files created:"
if [[ $SKIP_BASE -eq 0 ]]; then
  printf '  - %s\n' "${compose_base_file#"$BASE_DIR"/}"
fi
printf '  - %s\n' "${compose_instance_file#"$BASE_DIR"/}"
if [[ $create_env_example -eq 1 ]]; then
  printf '  - %s\n' "${env_example_file#"$BASE_DIR"/}"
fi
if [[ $WITH_DOCS -eq 1 ]]; then
  printf '  - %s\n' "${app_doc_file#"$BASE_DIR"/}"
fi

echo "[*] Bootstrap completed successfully."
