# Compose manifests quick guide

> See also the [Docker Compose combinations guide](../docs/COMPOSE_GUIDE.md) for full instructions and the overview of the [template structure](../docs/STRUCTURE.md).

## Recommended loading order

Manifests are chained in blocks. Each step inherits anchors and variables from the previous one.

1. `compose/docker-compose.base.yml` *(optional)* — defines anchors, named volumes, and shared variables. It is loaded automatically when present.
2. Instance compose file (`docker-compose.<instance>.yml`, e.g., `docker-compose.core.yml`) — consolidated definition for the instance. Add, remove, or scale services directly here.
3. Optional overlays (`compose/overlays/*.yml`) — ad-hoc adjustments appended after the base + instance pair.

```
(compose/docker-compose.base.yml) → docker-compose.core.yml → compose/overlays/<extra>.yml → ...
```

> The scripts (`scripts/deploy_instance.sh`, etc.) automatically follow this order when building the plan.

## Instances and service toggles

- **Main instances:** `core` and `media` are examples of full profiles. Their compose files (`docker-compose.core.yml` and `docker-compose.media.yml`) describe the complete stack for that environment (proxy labels, external networks, media mounts, caches, and the services themselves).
- **Enable/disable services:** keep service definitions inside each `docker-compose.<instance>.yml` and toggle them per environment using `profiles`, `deploy.replicas: 0`, or by removing the service block. There is no longer a `compose/apps/` directory; the instance file is the single source of truth for what runs.
- **Overlays for experiments:** append files from `compose/overlays/` when you need temporary changes (for example, feature flags or alternate storage classes) without editing the main instance compose file.

When building the stack, choose the instance compose file and overlays you want to load. The `core` instance can keep monitoring enabled, while `media` disables it by setting `deploy.replicas: 0` in `docker-compose.media.yml`, for example. Keeping the order ensures anchors defined in `compose/docker-compose.base.yml` (when present) remain available to any combination.

## Essential environment variables

| Variable | Where to define | Purpose | Reference |
| --- | --- | --- | --- |
| `TZ` | `env/common.example.env` | Ensures a consistent timezone for logs and schedules. | [env/README.md](../env/README.md#envcommonexampleenv) |
| `APP_DATA_DIR` / `APP_DATA_DIR_MOUNT` | `env/common.example.env` | Defines the persistent path (relative or absolute) used by the manifests. | [env/README.md](../env/README.md#envcommonexampleenv) |
| `APP_SHARED_DATA_VOLUME_NAME` | `env/common.example.env` | Standardizes the shared volume across multiple applications. | [env/README.md](../env/README.md#envcommonexampleenv) |
| `COMPOSE_EXTRA_FILES` | `env/<instance>.example.env` | Lists additional overlays applied after the default manifests. | [env/README.md](../env/README.md#como-gerar-arquivos-locais) |

> Use the [complete environment variables guide](../env/README.md) to review the latest list and document new fields. Secrets and per-service placeholders (such as `APP_SECRET`, `APP_RETENTION_HOURS`, and `WORKER_QUEUE_URL`) are detailed in the corresponding section of the [environment README](../env/README.md#placeholders-app-worker).

## Inspection tool

Run `scripts/describe_instance.sh <instance>` to audit the loaded manifests, active services, exposed ports, and resulting volumes from `docker compose config`. The `--list` flag reveals available instances, and `--format json` exports the metadata for automation.
