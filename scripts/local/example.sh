#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
scripts/local is reserved for project-specific overrides and is expected to be
replaced in downstream repos. Keep any scripts here narrowly scoped and tied to
your project so that template updates are easy to version and review.
EOF
