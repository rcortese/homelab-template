# Automation scripts quick guide

This directory concentrates the entrypoints used day to day to validate, deploy, and maintain stacks derived from the template. The sections below group helpers by category, summarize each script’s goal, and point to detailed descriptions in [`docs/OPERATIONS.md`](../docs/OPERATIONS.md).

## Root entrypoints vs `_internal/lib/` utilities

Files in `scripts/*.sh` are entrypoints ready for direct CLI execution (`scripts/<name>.sh`). They load helper functions from `scripts/_internal/lib/` using `source "$SCRIPT_DIR/_internal/lib/<file>.sh"` (for shell) or the equivalent Python modules when needed. The pattern `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` ensures each entrypoint finds repository-relative utilities, keeping behavior consistent even when run outside the project root.

Utilities under `scripts/_internal/lib/` are never executed alone: they expose reusable functions (for example, manifest composition, `.env` loading, step execution) that entrypoints import. When creating new scripts, reuse these libraries to avoid duplication and preserve already documented flows.

## Usage conventions

- **Resilient shell:** all Bash scripts adopt `set -euo pipefail` to abort on failures and prevent undeclared variables. Preserve this setting when writing new helpers.
- **Shared environment variables:** helpers accept variables such as `COMPOSE_INSTANCES`, `COMPOSE_EXTRA_FILES`, `DOCKER_COMPOSE_BIN`, and `APP_DATA_UID`/`APP_DATA_GID`, among others. `REPO_ROOT` is derived by the scripts and written to the generated root `.env` (do not set it manually). See each section in [`docs/OPERATIONS.md`](../docs/OPERATIONS.md) for details and export them before execution when you need to customize behavior.
- **External dependencies:** ensure Docker Compose v2 is available (`docker compose ...`) along with the tools used by linters (for example, `shfmt`, `shellcheck`, `checkbashisms`). Python snippets prefer the local Python interpreter and automatically install `requirements-dev.txt` dependencies if needed; only fallback to Docker (`python:3.11-slim`) when a local Python interpreter is unavailable or when containerized execution is explicitly required. Some flows also rely on `git`, `tar`, `jq`, and GNU coreutils.

## Catalog by category

### Validation

| Script | Summary | Reference |
| --- | --- | --- |
| `check_all.sh` | Chains structure, variable sync, and Compose validation in a single call before PRs (use `--with-quality-checks` to append the full quality suite). | [`docs/OPERATIONS.md#scriptscheck_allsh`](../docs/OPERATIONS.md#scriptscheck_allsh) |
| `check_structure.sh` | Ensures mandatory template directories and files are present. | [`docs/OPERATIONS.md#scriptscheck_structuresh`](../docs/OPERATIONS.md#scriptscheck_structuresh) |
| `check_env_sync.sh` | Compares Compose manifests with `env/*.example.env`, flagging missing or obsolete variables. | [`docs/OPERATIONS.md#scriptscheck_env_syncpy`](../docs/OPERATIONS.md#scriptscheck_env_syncpy) |
| `run_quality_checks.sh` | Gathers `pytest`, `shfmt`, `shellcheck`, and `checkbashisms` for quality validations. | [`docs/OPERATIONS.md#scriptsrun_quality_checkssh`](../docs/OPERATIONS.md#scriptsrun_quality_checkssh) |
| `validate_compose.sh` | Validates standard Docker Compose combinations for different profiles/instances. | [`docs/OPERATIONS.md#scriptsvalidate_composesh`](../docs/OPERATIONS.md#scriptsvalidate_composesh) |

### Deployment orchestration

| Script | Summary | Reference |
| --- | --- | --- |
| `deploy_instance.sh` | Runs the guided deployment flow (plans, validations, `docker compose up`, health check). | [`docs/OPERATIONS.md#scriptsdeploy_instancesh`](../docs/OPERATIONS.md#scriptsdeploy_instancesh) |
| `build_compose_file.sh` | Materializes the resolved Compose plan into a single file for reuse. | [`docs/OPERATIONS.md#scriptsbuild_compose_filesh`](../docs/OPERATIONS.md#scriptsbuild_compose_filesh) |
| `bootstrap_instance.sh` | Generates the initial structure for applications/instances, with support for documentation. | [`docs/OPERATIONS.md#scriptsbootstrap_instancesh`](../docs/OPERATIONS.md#scriptsbootstrap_instancesh) |

### Maintenance

| Script | Summary | Reference |
| --- | --- | --- |
| `fix_permission_issues.sh` | Adjusts permissions of persistent directories using the calculated instance context. | [`docs/OPERATIONS.md#scriptsfix_permission_issuessh`](../docs/OPERATIONS.md#scriptsfix_permission_issuessh) |
| `backup.sh` | Creates versioned snapshots of instance data and records the artifact location. | [`docs/OPERATIONS.md#scriptsbackupsh`](../docs/OPERATIONS.md#scriptsbackupsh) |
| `update_from_template.sh` | Reapplies customizations after syncing the fork with the original template. | [`docs/OPERATIONS.md#scriptsupdate_from_templatesh`](../docs/OPERATIONS.md#scriptsupdate_from_templatesh) |
| `detect_template_commits.sh` | Identifies the template base commit and the fork’s first unique commit. | [`docs/OPERATIONS.md#scriptsdetect_template_commitssh`](../docs/OPERATIONS.md#scriptsdetect_template_commitssh) |

### Diagnostics

| Script | Summary | Reference |
| --- | --- | --- |
| `describe_instance.sh` | Summarizes services, ports, and volumes for an instance (includes `--format json`). | [`docs/OPERATIONS.md#scriptsdescribe_instancesh`](../docs/OPERATIONS.md#scriptsdescribe_instancesh) |
| `check_health.sh` | Runs post-deploy checks to confirm the status of active services. | [`docs/OPERATIONS.md#scriptscheck_healthsh`](../docs/OPERATIONS.md#scriptscheck_healthsh) |
| `check_db_integrity.sh` | Performs inspections on SQLite databases with controlled application pauses. | [`docs/OPERATIONS.md#scriptscheck_db_integritysh`](../docs/OPERATIONS.md#scriptscheck_db_integritysh) |

> For additional scripts (for example, wrappers in `scripts/local/` or templates in `scripts/_internal/templates/`), replicate these conventions when documenting fork-specific extensions.
