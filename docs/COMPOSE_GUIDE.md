# Docker Compose combination guide

> Part of the [documentation index](./README.md). Read the [Overview](./OVERVIEW.md) to understand the role of each instance and align checklists with the runbooks for [core](./core.md) and [media](./media.md).

This guide documents how to build the Docker Compose plan using only the base file, the consolidated instance compose file, and any optional extra compose files. For a short view of the load order, see the [`compose/` README](../compose/README.md). Follow these instructions before running the generator that writes `docker-compose.yml` to the repository root.

> **Attention for forks:** all compose file names here are examples. Adjust directory, file, and service names according to step 3 of [How to start a derived project](../README.md#how-to-start-a-derived-project) when adapting the template to your stack.

## Manifest structure

| File type | Location | Role |
| --------------- | ----------- | ----- |
| **Base** | `compose/docker-compose.base.yml` (optional) | Holds only anchors and shared volumes reused by services. It is loaded automatically when present; if absent, the plan starts directly with the instance compose file. |
| **Instance compose** | `compose/docker-compose.<instance>.yml` (e.g., [`compose/docker-compose.core.yml`](../compose/docker-compose.core.yml), [`compose/docker-compose.media.yml`](../compose/docker-compose.media.yml)) | Declares every service that should run in the target environment. Use this file to wire networks, volumes, labels, and per-instance defaults without scattering overrides. |
| **Extra compose files** | Path(s) listed in `COMPOSE_EXTRA_FILES` or passed via `--file` (optional) | Ad-hoc adjustments layered after the base + instance pair. Ideal for temporary feature flags or experimentation without editing the main compose file. |

> **Note:** each instance file is self-contained and uses standard Compose features (`profiles`, `deploy.replicas`, conditional volumes) to decide what runs.

### Examples included in the template

- [`compose/docker-compose.core.yml`](../compose/docker-compose.core.yml) documents how to add reverse proxy labels, connect services to an external network (`core_proxy`), and declare named volumes (`core_logs`).
- [`compose/docker-compose.media.yml`](../compose/docker-compose.media.yml) shows how to share media mounts (`MEDIA_HOST_PATH`) between services and how to define a common volume for transcoding caches (`media_cache`).

### Service availability per instance

Use the instance compose file to control which services start:

- Keep services enabled by default and gate optional components behind `profiles` that you activate with `--profile <name>` or `COMPOSE_PROFILES`.
- Disable a service for an instance by setting `deploy.replicas: 0` or removing the block from that instance file.
- Keep per-instance tweaks (ports, paths, labels) close to the service definition instead of spreading them across multiple overrides.

## Stacks with multiple services

When combining several services, load the manifests in blocks (`compose/docker-compose.base.yml`, `compose/docker-compose.<instance>.yml`, and extra compose files) in the order shown below. This ensures anchors and variables are available before the services that consume them.

| Order | File | Purpose |
| ----- | ------- | ------ |
| 1 | `compose/docker-compose.base.yml` (when present) | Foundational structure with shared anchors. |
| 2 | `compose/docker-compose.<instance>.yml` (e.g., `compose/docker-compose.core.yml`, `compose/docker-compose.media.yml`) | Complete definition for the selected environment. |
| 3 | Extra compose files *(optional, repeatable)* | Extra adjustments layered after the main plan. |

> **Replace the placeholders:** `core`, `media`, and any other names used in the tables and examples are illustrative. Align each occurrence with the real instance name following step 3 of [How to start a derived project](../README.md#how-to-start-a-derived-project).

### Default flow with the generated `docker-compose.yml`

1. Generate the consolidated file with the helper:

   ```bash
   scripts/build_compose_file.sh --instance <instance> \
     --file compose/extra/<extra>.yml \           # optional, repeat if you need more than one
     --env-file env/local/common.env \             # optional override for the default chain
     --env-file env/local/<instance>.env           # optional instance override
   ```

   - Additional `--file` flags mirror `COMPOSE_EXTRA_FILES` when appending extra compose files.
   - `--env-file` lets you supply the env chain explicitly (for example, `env/local/common.env` then `env/local/<instance>.env`) when you need to test specific variables without touching the files under `env/local/`.
   - Re-run the command whenever manifests (`compose/docker-compose.<instance>.yml`, `compose/docker-compose.base.yml`, or extra compose files) change to refresh the root `docker-compose.yml`.

2. Use the generated file directly to start or inspect services:

   ```bash
   docker compose up -d
   docker compose ps
   ```

   The default command now targets the root `docker-compose.yml`, avoiding manual `-f` assembly and `--env-file` chains. This consolidated-file workflow is the supported path for running Compose commands and replaces earlier compatibility modes.

> Set `<instance>` to `core`, `media`, or any other name defined in your fork. Replace `<extra>` with real files whenever you need temporary or environment-specific adjustments.

### How to enable or disable optional components

- **Keep enabled**: leave the service block present in each `docker-compose.<instance>.yml`. When using `profiles`, add the profile to `COMPOSE_PROFILES` or the CLI command.
- **Disable selectively**: set `deploy.replicas: 0` or remove the service from the instance file where it should be off. This prevents accidental activations when adding new instances.
- **Remove globally**: delete the service definitions from every instance compose file when the component is no longer part of the stack.
- **Add another component**: declare the new service in each `docker-compose.<instance>.yml` where it should run, wiring dependencies directly in the same file.

> Whenever you update a service definition or the variable chain, regenerate `docker-compose.yml` before calling `docker compose up -d` to avoid divergence between the plan and the consolidated file.

### Generating an instance summary

Use `scripts/describe_instance.sh` to quickly inspect the applied manifests, resulting services, published ports, and mounted volumes. The script reuses the same planning chain as the deploy and validation flows and marks additional compose files loaded via `COMPOSE_EXTRA_FILES` or provided with `--file` in the generator.

```bash
scripts/describe_instance.sh core

scripts/describe_instance.sh media --format json
```

The default `table` format helps manual reviews, while `--format json` is ideal for automated documentation or feeding dashboards.

Example (`table` format):

```text
Instance: core

Compose files (-f):
  • compose/docker-compose.base.yml
  • compose/docker-compose.core.yml
  • compose/extra/metrics.yml (extra file)

Extra compose files applied:
  • compose/extra/metrics.yml

Services:
  - app
      Published ports:
        • 8080 -> 80/tcp
      Mounted volumes:
        • /srv/app/data -> /data/app (type=bind)
```

## Best practices

> Align any compose path mentioned below with step 3 of [How to start a derived project](../README.md#how-to-start-a-derived-project) whenever you rename instances in your fork.

- Always load `compose/docker-compose.base.yml` first when it exists.
- Keep each `docker-compose.<instance>.yml` self-contained: declare networks, volumes, and labels next to the services that consume them.
- Apply extra compose files after the main instance file and use them sparingly for temporary changes.
- Keep the file combination in sync with the environment variable chain (`env/local/common.env` → `env/local/<instance>.env`).
- Re-validate combinations with [`scripts/validate_compose.sh`](./OPERATIONS.md#scriptsvalidate_compose.sh) when any compose file changes.
