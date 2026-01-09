# Compose manifests quick guide

> See also the [Docker Compose combinations guide](../docs/COMPOSE_GUIDE.md) for full instructions and the overview of the [template structure](../docs/STRUCTURE.md).

## Recommended loading order

Manifests are chained in blocks. Each step inherits anchors and variables from the previous one.

1. `compose/docker-compose.common.yml` *(optional)* — defines shared services and shared resources (anchors, networks, volumes, variables) used by every instance. It is loaded automatically when present.
2. Instance compose file (`docker-compose.<instance>.yml`, e.g., `docker-compose.core.yml`) — consolidated definition for the instance. Add, remove, or scale services directly here.
3. Optional extra compose files — ad-hoc adjustments appended after the base + instance pair via `COMPOSE_EXTRA_FILES` or `--file`.

```
(compose/docker-compose.common.yml) → docker-compose.core.yml → <extra compose file> → ...
```

> The scripts (`scripts/deploy_instance.sh`, etc.) automatically follow this order when building the plan.

## Instances and service toggles

- **Main instances:** `core` and `media` are examples of full profiles. Their compose files (`docker-compose.core.yml` and `docker-compose.media.yml`) describe the complete stack for that environment (proxy labels, external networks, media mounts, caches, and the services themselves), layering any per-instance changes on top of shared definitions from `docker-compose.common.yml` when it exists.
- **Enable/disable services:** shared services that apply everywhere can live in `docker-compose.common.yml`; per-instance differences belong in `docker-compose.<instance>.yml`. If a service exists only in one instance, define it only in that instance file. Toggle services per environment using `profiles`, `deploy.replicas: 0`, or by removing the service block.
- **Extra compose files for experiments:** append extra files when you need temporary changes (for example, feature flags or alternate storage classes) without editing the main instance compose file.

When building the stack, choose the instance compose file and any extra compose files you want to load. The `core` instance can keep monitoring enabled, while `media` disables it by setting `deploy.replicas: 0` in `docker-compose.media.yml`, for example. Keeping the order ensures anchors defined in `compose/docker-compose.common.yml` (when present) remain available to any combination.

## Essential environment variables

| Variable | Where to define | Purpose | Reference |
| --- | --- | --- | --- |
| `TZ` | `env/common.example.env` | Ensures a consistent timezone for logs and schedules. | [env/README.md](../env/README.md#envcommonexampleenv) |
| `REPO_ROOT` | `env/<instance>.example.env` | Absolute path to the repository root for persistent mounts. | [env/README.md](../env/README.md#variable-mapping) |
| `APP_SHARED_DATA_VOLUME_NAME` | `env/common.example.env` | Standardizes the shared volume across multiple applications. | [env/README.md](../env/README.md#envcommonexampleenv) |
| `COMPOSE_EXTRA_FILES` | `env/<instance>.example.env` | Lists additional compose files applied after the default manifests. | [env/README.md](../env/README.md#como-gerar-arquivos-locais) |

> Use the [complete environment variables guide](../env/README.md) to review the latest list and document new fields. Secrets and per-service placeholders (such as `APP_SECRET`, `APP_RETENTION_HOURS`, and `WORKER_QUEUE_URL`) are detailed in the corresponding section of the [environment README](../env/README.md#placeholders-app-worker).

## Inspection tool

Run `scripts/describe_instance.sh <instance>` to audit the loaded manifests, active services, exposed ports, and resulting volumes from `docker compose config`. The `--list` flag reveals available instances, and `--format json` exports the metadata for automation.
