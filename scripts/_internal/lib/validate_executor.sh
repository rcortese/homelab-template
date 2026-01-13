#!/usr/bin/env bash

# Helpers to execute docker compose validation for each instance.

VALIDATE_EXECUTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/_internal/lib/validate_plan.sh
source "$VALIDATE_EXECUTOR_DIR/validate_plan.sh"

# shellcheck source=scripts/_internal/lib/validate_output.sh
source "$VALIDATE_EXECUTOR_DIR/validate_output.sh"

# shellcheck source=scripts/_internal/lib/validate_runner.sh
source "$VALIDATE_EXECUTOR_DIR/validate_runner.sh"
