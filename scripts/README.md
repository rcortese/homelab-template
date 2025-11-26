# Automation scripts quick guide

This directory concentrates the entrypoints used day to day to validate, deploy, and maintain stacks derived from the template. The sections below group helpers by category, summarize the goal of each script, and point to detailed descriptions in [`docs/OPERATIONS.md`](../docs/OPERATIONS.md).

## Root entrypoints vs. utilities in `lib/`

Files in `scripts/*.sh` and `scripts/*.py` are entrypoints ready for direct execution via CLI (`scripts/<name>.sh`). They load helper functions from `scripts/lib/` using `source "$SCRIPT_DIR/lib/<file>.sh"` (for shell) or the equivalent Python modules when needed. The pattern `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` ensures each entrypoint can find repository-relative utilities, keeping behavior consistent even outside the project root.

Utilities in `scripts/lib/` are never executed on their own: they expose reusable functions (for example, manifest composition, `.env` loading, step execution) that are imported by entrypoints. When creating new scripts, reuse these libraries to avoid duplication and preserve documented flows.

## Usage conventions

- **Resilient shell:** all Bash scripts adopt `set -euo pipefail` to abort on failures and prevent undeclared variables. Preserve this configuration when writing new helpers.
- **Shared environment variables:** helpers accept variables such as `COMPOSE_INSTANCES`, `COMPOSE_EXTRA_FILES`, `DOCKER_COMPOSE_BIN`, `APP_DATA_DIR`, `APP_DATA_DIR_MOUNT`, `APP_DATA_UID`/`APP_DATA_GID`, among others. See each section in [`docs/OPERATIONS.md`](../docs/OPERATIONS.md) for details and export them before execution when you need to customize behavior.
- **External dependencies:** ensure Docker Compose v2 is available (`docker compose ...`) along with tools used by linters (for example, `shfmt`, `shellcheck`, `checkbashisms`). Python snippets run via the official image (`python:3.11-slim`) when Docker is present; the local Python 3 runtime is used only as a fallback and automatically installs the dependencies from `requirements-dev.txt` if needed. Some flows also use `git`, `tar`, `jq`, and standard GNU coreutils.

## Catalog by category

### Validations

| Script | Summary | Reference |
| --- | --- | --- |
| `check_all.sh` | Chains structure, variable synchronization, and Compose validation in a single call before PRs. | [`docs/OPERATIONS.md#scriptscheck_allsh`](../docs/OPERATIONS.md#scriptscheck_allsh) |
| `check_structure.sh` | Ensures mandatory template directories and files are present. | [`docs/OPERATIONS.md#scriptscheck_structuresh`](../docs/OPERATIONS.md#scriptscheck_structuresh) |
| `check_env_sync.sh` | Compares Compose manifests with `env/*.example.env`, flagging missing or obsolete variables. | [`docs/OPERATIONS.md#scriptscheck_env_syncpy`](../docs/OPERATIONS.md#scriptscheck_env_syncpy) |
| `run_quality_checks.sh` | Groups `pytest`, `shfmt`, `shellcheck`, and `checkbashisms` for quality validations. | [`docs/OPERATIONS.md#scriptsrun_quality_checkssh`](../docs/OPERATIONS.md#scriptsrun_quality_checkssh) |
| `validate_compose.sh` | Validates standard Docker Compose combinations for different profiles/instances. | [`docs/OPERATIONS.md#scriptsvalidate_composesh`](../docs/OPERATIONS.md#scriptsvalidate_composesh) |

### Deployment orchestration

| Script | Summary | Reference |
| --- | --- | --- |
| `deploy_instance.sh` | Runs the guided deployment flow (plans, validations, `docker compose up`, health check). | [`docs/OPERATIONS.md#scriptsdeploy_instancesh`](../docs/OPERATIONS.md#scriptsdeploy_instancesh) |
| `compose.sh` | Standardizes `docker compose` calls using the template manifests and variables. | [`docs/OPERATIONS.md#scriptscomposesh`](../docs/OPERATIONS.md#scriptscomposesh) |
| `bootstrap_instance.sh` | Generates the initial structure of applications/instances with support for overrides and documentation. | [`docs/OPERATIONS.md#scriptsbootstrap_instancesh`](../docs/OPERATIONS.md#scriptsbootstrap_instancesh) |

### Maintenance

| Script | Summary | Reference |
| --- | --- | --- |
| `fix_permission_issues.sh` | Adjusts permissions of persistent directories using the instance’s calculated context. | [`docs/OPERATIONS.md#scriptsfix_permission_issuessh`](../docs/OPERATIONS.md#scriptsfix_permission_issuessh) |
| `backup.sh` | Creates versioned snapshots of instance data and records the artifact location. | [`docs/OPERATIONS.md#scriptsbackupsh`](../docs/OPERATIONS.md#scriptsbackupsh) |
| `update_from_template.sh` | Reapplies customizations after syncing the fork with the original template. | [`docs/OPERATIONS.md#scriptsupdate_from_templatesh`](../docs/OPERATIONS.md#scriptsupdate_from_templatesh) |
| `detect_template_commits.sh` | Identifies the template base commit and the first commit exclusive to the fork. | [`docs/OPERATIONS.md#scriptsdetect_template_commitssh`](../docs/OPERATIONS.md#scriptsdetect_template_commitssh) |

### Diagnostics

| Script | Summary | Reference |
| --- | --- | --- |
| `describe_instance.sh` | Summarizes services, ports, and volumes of an instance (includes `--format json` mode). | [`docs/OPERATIONS.md#scriptsdescribe_instancesh`](../docs/OPERATIONS.md#scriptsdescribe_instancesh) |
| `check_health.sh` | Runs post-deploy checks to confirm the status of active services. | [`docs/OPERATIONS.md#scriptscheck_healthsh`](../docs/OPERATIONS.md#scriptscheck_healthsh) |
| `check_db_integrity.sh` | Performs inspections on SQLite databases with controlled pauses for the involved applications. | [`docs/OPERATIONS.md#scriptscheck_db_integritysh`](../docs/OPERATIONS.md#scriptscheck_db_integritysh) |

> For additional scripts (for example, wrappers in `scripts/local/` or templates in `scripts/templates/`), replicate these conventions when documenting fork-specific extensions.
