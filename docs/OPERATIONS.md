# Template standard operations

> See the [documentation index](./README.md) and adapt this guide to reflect your stack.

This document offers a starting point for describing operational processes and how to use the scripts shipped with the template. When deriving a repository, adapt the examples below with concrete commands for your service.

> Looking only for a quick map of available scripts? See [`scripts/README.md`](../scripts/README.md) for the catalog grouped by category and to quickly find the desired helper.

| Script | Purpose | Basic command | Recommended triggers |
| --- | --- | --- | --- |
| [`scripts/check_all.sh`](#scriptscheck_allsh) | Aggregate structure, `.env`, and Compose validations in a single command. | `scripts/check_all.sh` | Before opening PRs or running full local pipelines. |
| [`scripts/check_structure.sh`](#scriptscheck_structuresh) | Confirm required directories/files. | `scripts/check_structure.sh` | Before PRs or pipelines that reorganize files. |
| [`scripts/check_env_sync.sh`](#scriptscheck_env_syncsh) | Verify synchronization between Compose and `env/*.example.env`. | `scripts/check_env_sync.sh` | After editing Compose or `.env` templates; in local/CI validations. |
| [`scripts/run_quality_checks.sh`](#scriptsrun_quality_checkssh) | Run `pytest`, `shfmt`, `shellcheck`, and `checkbashisms` in one go. | `scripts/run_quality_checks.sh` | After changes to Python or shell code. |
| [`scripts/bootstrap_instance.sh`](#scriptsbootstrap_instancesh) | Create initial application/instance structure. | `scripts/bootstrap_instance.sh <app> <instance>` | When starting new services or environments. |
| [`scripts/validate_compose.sh`](#scriptsvalidate_composesh) | Validate standard Docker Compose combinations. | `scripts/validate_compose.sh` | After adjusting manifests; CI stages. |
| [`scripts/deploy_instance.sh`](#scriptsdeploy_instancesh) | Orchestrate guided instance deployment. | `scripts/deploy_instance.sh <target>` | Manual or automated deployments. |
| [`scripts/fix_permission_issues.sh`](#scriptsfix_permission_issuessh) | Adjust permissions for persistent directories. | `scripts/fix_permission_issues.sh <instance>` | Before starting services that share storage. |
| [`scripts/backup.sh`](#scriptsbackupsh) | Generate a versioned snapshot of the instance. | `scripts/backup.sh <instance>` | Backup routines and pre-invasive changes. |
| [`scripts/build_compose_file.sh`](#scriptsbuild_compose_filesh) | Generate the root `docker-compose.yml` for direct `docker compose` use. | `scripts/build_compose_file.sh <name>` | Before running Compose commands; after manifest or `.env` changes. |
| [`scripts/describe_instance.sh`](#scriptsdescribe_instancesh) | Summarize services, ports, and volumes of an instance. | `scripts/describe_instance.sh <instance>` | Quick audits or runbook generation. |
| [`scripts/check_health.sh`](#scriptscheck_healthsh) | Check service status after changes. | `scripts/check_health.sh <instance>` | Post-deploy, post-restore, or troubleshooting. |
| [`scripts/check_db_integrity.sh`](#scriptscheck_db_integritysh) | Validate SQLite integrity with controlled pause. | `scripts/check_db_integrity.sh <instance>` | Scheduled maintenance or failure investigation. |
| [`scripts/detect_template_commits.sh`](#scriptsdetect_template_commitssh) | Identify the template base commit and the first fork-exclusive commit. | `scripts/detect_template_commits.sh` | Before following the [update from the original template](../README.md#updating-from-the-original-template) flow or reviewing local divergences. |
| [`scripts/update_from_template.sh`](#scriptsupdate_from_templatesh) | Reapply customizations after updating the template. | See the [canonical guide](../README.md#updating-from-the-original-template). | When syncing forks with upstream. |

## Before you start

- Ensure local `.env` files were generated from the models described in [`env/README.md`](../env/README.md).
- Review the manifest combinations (including `compose/docker-compose.common.yml` when present, `compose/docker-compose.<instance>.yml` when present, and overrides) the scripts will use. The sample [`compose/docker-compose.core.yml`](../compose/docker-compose.core.yml) and [`compose/docker-compose.media.yml`](../compose/docker-compose.media.yml) files document how to apply global per-instance adjustments before the application manifests. Regenerate the consolidated `docker-compose.yml` with `scripts/build_compose_file.sh <instance>` whenever manifests or variables change.
- Run `scripts/check_all.sh` to validate structure, variable synchronization, and Compose manifests before opening PRs or publishing local changes.
- Run `scripts/check_env_sync.sh` whenever you edit manifests or `.env` templates to ensure variables stay synchronized.
- Document extra dependencies (CLIs, credentials, registry access) in additional sections.
- Prefer running the Python helpers locally (install `requirements-dev.txt` when present) and only fall back to Docker when a local interpreter is unavailable or when isolating dependencies from the host is a requirement.

<a id="generic-deploy-and-post-deploy-checklist"></a>
## Generic deploy and post-deploy checklist

> Use this checklist as a common baseline for all environments derived from this template.

### Preparation

1. Update `env/local/<instance>.env` with the latest variables before generating or applying manifests.
2. Review [Stacks with multiple applications](./COMPOSE_GUIDE.md#stacks-with-multiple-applications) to confirm which services should be enabled or disabled for the current cycle.
3. Validate manifests with `scripts/validate_compose.sh` (or equivalent) to ensure the combination of files remains consistent.
4. Generate a summary with `scripts/describe_instance.sh <instance>`; when you need audit trail or supporting material, also save the `--format json` output alongside the deployment checklist.

### Execution

1. Run the guided deployment flow:
   ```bash
   scripts/deploy_instance.sh <instance>
   ```
   The helper regenerates `./docker-compose.yml` and `./.env` before calling `docker compose` to ensure the generated root outputs reflect recent manifest or `.env` edits (make changes in `compose/` or `env/*.example.env`, then rerun the generator).
2. Record relevant outputs (image hashes used, pipeline or artifact versions applied) for future reference.

### Post-deploy

1. Run `scripts/check_health.sh <instance>` — or an equivalent check — to validate the state of the newly deployed services.
2. Review dashboards, critical alerts, and integrations that depend on the instance, ensuring metrics and notifications return to expected behavior.

### Configuring the shared internal network

- Use the placeholders defined in `env/common.example.env` for the network name, driver, subnet, and gateway (`APP_NETWORK_NAME`, `APP_NETWORK_DRIVER`, `APP_NETWORK_SUBNET`, `APP_NETWORK_GATEWAY`). Adjust them to your environment topology before generating the real files under `env/local/`.
- Each instance should reserve unique IPv4 addresses for the services. The `env/core.example.env` and `env/media.example.env` models illustrate how to split IPs for the `app` service (`APP_NETWORK_IPV4`), the `monitoring` service (`MONITORING_NETWORK_IPV4`), and the worker service (`WORKER_CORE_NETWORK_IPV4` and `WORKER_MEDIA_NETWORK_IPV4`). When present, [`compose/docker-compose.core.yml`](../compose/docker-compose.core.yml) shows how to connect the `app` service to an external network (`core_proxy`) using `CORE_PROXY_NETWORK_NAME` and `CORE_PROXY_IPV4` as placeholders.
- When creating new instances or additional services, replicate the pattern: declare instance-specific `*_NETWORK_IPV4` variables in the corresponding `.env` template and connect the service to the `homelab_internal` network (or the name defined in `APP_NETWORK_NAME`) inside the Compose manifest.
- After adjusting the IPs, run `scripts/validate_compose.sh` or `docker compose config -q` to confirm there are no overlaps or gaps in the configuration.

## scripts/check_all.sh

- **Order of checks:**
  1. `scripts/check_structure.sh` — ensures required directories and files are present.
  2. `scripts/check_env_sync.sh` — validates synchronization between Compose manifests and `env/*.example.env` files.
  3. `scripts/validate_compose.sh` — confirms Compose combinations remain valid for supported profiles.
- **Optional quality checks:** pass `--with-quality-checks` to invoke `scripts/run_quality_checks.sh` immediately after the Compose validation. This keeps the default path focused on structural checks while allowing an opt-in full quality sweep.
- **Failure behavior:** the script runs with `set -euo pipefail` and stops at the first check that returns a non-zero exit code, propagating the message from the helper that failed.
- **Relevant variables and flags:** use `--with-quality-checks` for the optional quality suite, and export variables accepted by internal scripts (`COMPOSE_INSTANCES`, `COMPOSE_EXTRA_FILES`, `DOCKER_COMPOSE_BIN`, among others) when you need to customize the chain.
- **Usage guidance:** prioritize `scripts/check_all.sh` in full validation cycles before opening PRs, syncing forks, or starting manual pipelines. Use the individual scripts only during focused adjustments (for example, running `scripts/check_env_sync.sh` after editing a `.env`). Reproduce the call in CI pipelines that mirror the local validation flow to keep parity across environments.

## scripts/check_structure.sh

See the summary in the table above. Include `scripts/check_env_sync.sh` in local or CI runs to keep manifests and variables aligned.

## scripts/check_env_sync.sh

- **Purpose:** compare the manifests (`compose/docker-compose.common.yml`, when present, plus detected overrides) with the corresponding `env/*.example.env` files and flag divergences. The shell wrapper (`scripts/check_env_sync.sh`) prefers running via Docker (`python:3.11-slim`) and falls back to local Python only when necessary, using `scripts/check_env_sync.py` as the main module.
- **Typical usage:**
  ```bash
  scripts/check_env_sync.sh
  scripts/check_env_sync.sh --repo-root /alternate/path
  scripts/check_env_sync.sh --instance core --instance media
  ```
- **Output:** lists missing or obsolete variables and instances without a template, returning a non-zero exit code when issues are found — ideal for CI.
- **Filtering by instance:** use the repeatable `--instance` flag to focus validation on a specific subset without exporting global variables. Combine it with the other parameters when you want to compare only a reduced set during iterative adjustments.
- **Best practices:** run the script after changes to Compose or example `.env` files and include it in the local validation pipeline before opening PRs.
  > **Warning:** running the verification before opening PRs prevents orphan variables from reaching review.

### Allowing project-specific implicit variables

- **Local override:** derived projects can create `scripts/local/check_env_sync.py` with an `IMPLICIT_ENV_VARS` set to whitelist extra variables that should not appear in `env/*.example.env` (for example, secrets injected only in production). See the template in [`scripts/local/README.md`](../scripts/local/README.md).
- **When to use:** add variables that are intentionally absent from the example templates but required by Compose or auxiliary scripts. Keep the list small and documented so forks know why each entry is skipped by the sync checker.
- **Minimal example:**
  ```yaml
  services:
    app:
      environment:
        - NEW_RELIC_LICENSE_KEY=${NEW_RELIC_LICENSE_KEY}
  ```
  ```python
  """Local overrides for check_env_sync."""

  from typing import Set

  IMPLICIT_ENV_VARS: Set[str] = {
      "NEW_RELIC_LICENSE_KEY",
  }
  ```

## scripts/run_quality_checks.sh

- **Purpose:** concentrate the base quality suite (`python -m pytest`, `shfmt`, `shellcheck`, and `checkbashisms` across repository scripts) into a single command.
- **Typical usage:**
  ```bash
  scripts/run_quality_checks.sh
  scripts/run_quality_checks.sh --no-lint
  ```
- **Customization:** set `PYTHON_RUNTIME_IMAGE`/`PYTHON_RUNTIME_REQUIREMENTS_FILE` to customize container execution or `PYTHON_RUNTIME_SKIP_REQUIREMENTS=1` to reuse dependencies already installed locally. You can also adjust `SHFMT_BIN`, `SHELLCHECK_BIN`, or `CHECKBASHISMS_BIN` to point to alternative binaries when needed, and pass `--no-lint` when you only want to run the Python test suite.
- **Best practices:** run the helper during iterative cycles on Python or shell code to quickly catch regressions and mirror the call in local pipelines before running `scripts/check_all.sh`.

## scripts/bootstrap_instance.sh

Use `--base-dir` and `--with-docs` to explicitly declare alternate directories and generate initial documentation. After bootstrapping, adjust the instance compose file (`docker-compose.<instance>.yml`), fill in `env/<instance>.example.env`, and extend `docs/apps/<component>.md`.
- **Quick example:**
  ```bash
  scripts/bootstrap_instance.sh my-app prod --with-docs
  ```

<a id="scriptsvalidate_compose.sh"></a>
## scripts/validate_compose.sh

- **Useful parameters:**
  - `COMPOSE_INSTANCES` — list of environments to validate (space- or comma-separated).
  - `DOCKER_COMPOSE_BIN` — alternate path to the binary.
  - `COMPOSE_EXTRA_FILES` — optional list of extra compose files applied after the standard override (accepts spaces or commas).
- The script generates a consolidated `docker-compose.yml` in the repository root before invoking
  `docker compose config -q`.
- **Practical examples:**
  - Default run using only the configured base and override manifests:
    ```bash
    scripts/validate_compose.sh
    ```
  - Simultaneous validation of multiple instances defined in `COMPOSE_INSTANCES`:
    ```bash
    COMPOSE_INSTANCES="prod staging" scripts/validate_compose.sh
    ```
  - Applying extra compose files listed in `COMPOSE_EXTRA_FILES`:
    ```bash
    COMPOSE_EXTRA_FILES="compose/extra/metrics.yml" scripts/validate_compose.sh
    ```

  > The planning helper automatically assembles `compose/docker-compose.common.yml` (when present), the selected `docker-compose.<instance>.yml`, and any extra compose files listed in `COMPOSE_EXTRA_FILES`, producing the root `docker-compose.yml` used for validation.

  > Variables can be pre-exported (`export COMPOSE_INSTANCES=...`) or prefixed to the command, keeping the flow simple.
  > **Warning:** use validation to confirm that the standard Compose combinations remain compatible with active profiles before deployments or PRs.

## scripts/deploy_instance.sh

Beyond the main flags (`--force`, `--skip-structure`, `--skip-validate`, `--skip-health`), customize prompts and file combinations to reflect real environments. Set `COMPOSE_EXTRA_FILES` in `env/local/common.env` or `env/local/<instance>.env` when additional compose files are needed (the root `.env` is generated). The script calculates the persistent directory from `APP_DATA_DIR` (relative path) or `APP_DATA_DIR_MOUNT` (absolute path) — leave both empty to fall back to `data/<instance>/<app>` and never enable both variables simultaneously, as the routine aborts with an error.

## scripts/fix_permission_issues.sh

The script relies on `scripts/lib/deploy_context.sh` to calculate `APP_DATA_DIR` or `APP_DATA_DIR_MOUNT`, plus `APP_DATA_UID` and `APP_DATA_GID`. In shared environments, combine execution with `--dry-run` to review changes before applying `chown`. Document exceptions to the `data/<instance>/<app>` relative pattern, and remember that only one of the variables (`APP_DATA_DIR` or `APP_DATA_DIR_MOUNT`) can be defined.

## scripts/backup.sh

- **Dependencies:**
  - The instance `env/local/<instance>.env` must be up to date so that `scripts/lib/deploy_context.sh` can identify `APP_DATA_DIR` and other variables used to assemble the stack and compose plan;
  - The `backups/` directory must be writable (the script creates subfolders automatically but respects host permissions);
  - It is recommended to ensure the instance env file is sourced (`source env/local/<instance>.env`) when there are extra exports required by services.
- The default command (`scripts/backup.sh core`) generates a full snapshot of the instance and reports the artifact location at the end. See [`docs/BACKUP_RESTORE.md`](./BACKUP_RESTORE.md) for retention and restore practices.
- **Customization tips for forks:**
  - Export complementary variables (for example, `EXTRA_BACKUP_PATHS` or credentials for external repositories) before calling the script, allowing local wrappers to include extra directories or send artifacts to remote storage.
  - Adjust `env/local/<instance>.env` to set `APP_DATA_DIR` (relative) or `APP_DATA_DIR_MOUNT` (absolute) when the data layout differs from the `data/<instance>/<app>` default — never enable both at the same time.
  - Extend the flow in external wrappers by adding pre/post-backup hooks (helper scripts, notifications, or compression) while keeping the stop/copy/restart logic encapsulated here.

## scripts/build_compose_file.sh

- **Goal:** materialize the resolved Compose plan into `docker-compose.yml` at the repository root and consolidate the applied env chain into `.env`, so that the standard commands become `docker compose up -d` and `docker compose ps` without extra flags.
- **Generated outputs:** `./docker-compose.yml` and `./.env` are generated files. Edit the source manifests or `env/*.example.env` templates and rerun the script instead of modifying the root outputs directly.
- **Inputs and overrides:**
  - Requires the instance argument to reuse the standard discovery chain (base manifests, app compose files, and per-instance overrides).
  - Use `COMPOSE_EXTRA_FILES` in `env/local/common.env` or `env/local/<instance>.env` when optional compose files should be merged into the plan.
  - Adjust `COMPOSE_ENV_FILES` (or the default `env/local/common.env` → `env/local/<instance>.env` chain) to control the consolidated `.env` content.
  - `--env-output` changes where the consolidated `.env` is written (defaults to the repository root). The helper rebuilds the file on every run, honoring the same precedence applied to `COMPOSE_ENV_FILES`.
- **Output validation:** after writing the merged files, the script runs `docker compose config -q` (reusing the same env chain) and fails when inconsistencies are detected. Re-run the generator whenever manifests or variables are modified to keep the root file and generated `.env` in sync.
- **Examples:**
  ```bash
  # Generate the root docker-compose.yml and .env for the core instance using defaults
  scripts/build_compose_file.sh core

  # Write the consolidated .env to a different path
  scripts/build_compose_file.sh media --env-output /tmp/media.env
  ```

## scripts/describe_instance.sh

- **Discover available instances:** run `scripts/describe_instance.sh --list` to confirm which combinations the template exposes before requesting a specific summary.
- **Available formats:**
  - `table` (default) — ideal for quick terminal or runbook reviews.
  - `json` — aimed at automated integrations and documentation generation.
- The `table` output helps quick reviews. With `--format json`, fields such as `compose_files`, `extra_files`, and `services` can feed runbook generators or status pages.
- The report is generated from the consolidated `docker-compose.yml` produced by `scripts/build_compose_file.sh`, so keep that file up to date when manifests or env templates change.

## scripts/check_health.sh

- **Supported arguments and variables:**
  - `HEALTH_SERVICES` — list of services to inspect (space- or comma-separated). When set, execution is limited to the desired services only.
  - `COMPOSE_ENV_FILES` — optional list of `.env` files applied before querying `docker compose`, overriding the default `env/local/common.env` → `env/local/<instance>.env` chain when provided.
- Collection generates (or requires) a consolidated `docker-compose.yml` via `scripts/build_compose_file.sh` before running `docker compose ps/logs`.
- `COMPOSE_EXTRA_FILES` overrides are ignored here; customize the compose plan through `scripts/build_compose_file.sh` instead.
- The script automatically supplements the service list by running `docker compose config --services`. If no services are found, execution aborts with an error to avoid silently suppressing logs.
- **Output formats:**
  - `text` (default) — mirrors the historical behavior by printing `docker compose ps` followed by recent logs.
  - `json` — serializes container status (including `docker compose ps --format json`, when available) and logs for each monitored service for consumption by pipelines or status pages.
- **Persisting output:** use `--output <file>` to write the report to disk while still printing to stdout, making it easier to version or distribute the result.

Practical examples:

```bash
# Traditional text output
scripts/check_health.sh core

# Structured collection for pipelines (e.g., GitHub Actions + jq)
scripts/check_health.sh --format json core | jq '.logs.failed'

# Generate a JSON file to publish on a status page
scripts/check_health.sh --format json --output status/core.json core

# Use HEALTH_SERVICES to limit collection to critical services
HEALTH_SERVICES="api worker" scripts/check_health.sh --format json media | jq '.compose.raw'
```

> **Tip:** combine `json` mode with tools like `jq`, `yq`, or HTTP clients (`curl`, `gh api`) to feed dashboards and notifications. The `logs.entries[].log` field carries the text content, while `logs.entries[].log_b64` preserves Base64 data for safe reprocessing.

## scripts/check_db_integrity.sh

- **Useful parameters:**
  - `--data-dir` — root directory where `.db` files will be searched.
  - `--format` — switches between `text` (default) and `json` outputs for automated integrations.
  - `--no-resume` — prevents automatically resuming services at the end of the check (useful for manual investigations).
  - `--output` — writes the final summary (text or JSON, according to the chosen format) to the given path.
  - `SQLITE3_MODE` — sets the backend (`container`, `binary`, or `auto`; default `container`).
  - `SQLITE3_CONTAINER_RUNTIME` — runtime used to execute the container (default `docker`).
  - `SQLITE3_CONTAINER_IMAGE` — image used for the `sqlite3` command (default `keinos/sqlite3:latest`).
  - `SQLITE3_BIN` — path to a local binary used in `binary` mode or as a fallback.
- **Operational notes:**
  - The script builds (or requires) `docker-compose.yml` for the instance before pausing services, relying on the consolidated file for all Compose commands.
  - Backups with the `.bak` suffix are automatically generated before overwriting a recovered database.
  - Whenever an inconsistency is detected (even after recovery), alerts are emitted to stderr to ease integration with monitoring systems.
  - Combine with short maintenance windows because services stay paused during the entire inspection.

## scripts/update_from_template.sh

This document keeps only a summary: use `scripts/update_from_template.sh` to reapply customizations after syncing the fork with the template. For the detailed walkthrough, explained parameters, and execution examples, see the ["Updating from the original template"](../README.md#updating-from-the-original-template) section in `README.md`, which is the single source of truth for this flow. Record here only local adaptations that do not conflict with the main guide.

## scripts/detect_template_commits.sh

- **Main parameters:**
  - `--remote` — explicitly sets the remote pointing to the template; detected automatically when possible.
  - `--target-branch` — provides the template branch used as reference; when omitted, the script attempts to discover the default HEAD (`main`/`master`).
  - `--output` — overrides the default `env/local/template_commits.env` path when saving the calculated hashes.
  - `--no-fetch` — avoids running `git fetch --prune` before calculations, useful when the local mirror is already up to date.
- **Generated output:** creates (or updates) `env/local/template_commits.env` with `ORIGINAL_COMMIT_ID` and `FIRST_COMMIT_ID`, allowing reuse of the values in the next step of the ["Updating from the original template"](../README.md#updating-from-the-original-template) flow.
- **Examples aligned with the standard flow:**
  - Automatic detection before running `scripts/update_from_template.sh`:
    ```bash
    scripts/detect_template_commits.sh
    ```
  - Forcing remote, source branch, and reusing the README-suggested output:
    ```bash
    scripts/detect_template_commits.sh \
      --remote template \
      --target-branch main \
      --output env/local/template_commits.env
    ```
  - In pipelines that already updated the template refs, combine with `--no-fetch` to speed up the process:
    ```bash
    scripts/detect_template_commits.sh --no-fetch
    ```

## Suggested customizations

- **New service:** use `scripts/bootstrap_instance.sh <instance>` (or your preferred scaffolding) as a starting point; then declare the service inside `docker-compose.<instance>.yml`, customize `env/local/<instance>.env`, and update documentation before proceeding with validations.
- **Persistent directories:** the `data/<instance>/<app>` path is calculated automatically; use `APP_DATA_DIR` (relative) **or** `APP_DATA_DIR_MOUNT` (absolute) when you need to customize the destination and adjust `APP_DATA_UID`/`APP_DATA_GID` in `env/local/<instance>.env` (or `env/local/common.env`) to align permissions.
- **Monitored services:** set `HEALTH_SERVICES` in `env/local/<instance>.env` or via `COMPOSE_ENV_FILES` so `scripts/check_health.sh` targets the correct logs.
- **Extra volumes:** add mounts directly to the relevant service inside `docker-compose.<instance>.yml` to expose different paths per environment. When present, see also [`docker-compose.media.yml`](../docker-compose.media.yml) for an example of a named volume shared (`media_cache`) between services in the instance.
- **Configurable extra compose files:** register optional files and enable them per environment via `COMPOSE_EXTRA_FILES` when building `docker-compose.yml`. The health and audit helpers operate on the generated root file, not direct compose file chains.

## Suggested operational flows

1. **Regular deployments:** describe the step-by-step (pre-validations, deployment command, post-checks) for each environment.
2. **Updates:** document how to apply image, dependency, or configuration upgrades.
3. **Backups & restores:** integrate this guide with [`docs/BACKUP_RESTORE.md`](./BACKUP_RESTORE.md) and detail where artifacts are stored.
4. **Troubleshooting:** list quick commands to collect logs, metrics, or restart services.

Update or replace entire sections as needed to accurately represent the operational lifecycle of the derived project.
