# Compose manifests quick guide

> See also the [Docker Compose combinations guide](../docs/COMPOSE_GUIDE.md) for full instructions and the overview of the [template structure](../docs/STRUCTURE.md).

## Recommended loading order

Manifests are chained in blocks. Each step inherits anchors and variables from the previous one.

1. `compose/base.yml` *(optional)* — defines anchors, named volumes, and shared variables. It is loaded automatically when present.
2. Instance manifest (`compose/<instance>.yml`, e.g., `compose/core.yml`) *(optional)* — enables networks, labels, and global volumes when present.
3. Enabled applications (`compose/apps/<app>/...`) — each application comes in a `base.yml` + `<instance>.yml` pair.

```
(base.yml) → core.yml|media.yml → compose/apps/app/base.yml → compose/apps/app/<instance>.yml → ...
```

> The scripts (`scripts/compose.sh`, `scripts/deploy_instance.sh`, etc.) automatically follow this order when building the plan.

## Main instances and optional applications

- **Main instances:** `core` and `media` are examples of full profiles. Their manifests (`compose/core.yml` and `compose/media.yml`, when present) load settings shared by all applications in that instance (proxy labels, external networks, media mounts, caches, etc.).
- **Primary application:** `compose/apps/app/` illustrates a standard application. The `base.yml` file introduces services and anchors that will be specialized in the `core.yml` and `media.yml` overrides.
- **Auxiliary applications:** directories such as `compose/apps/monitoring/` and `compose/apps/worker/` demonstrate how to enable optional components. Simply include the desired `base.yml` + `<instance>.yml` pair after the active instance manifest. Services without a `base.yml` are treated as *override-only* and are only attached to instances where the file exists.

When building the stack, choose which application blocks to attach. The `core` instance can run `app` + `monitoring`, while `media` loads only `app` + `worker`, for example. Keeping the order ensures anchors defined in `compose/base.yml` (when present) remain available to any combination.

## Essential environment variables

| Variable | Where to define | Purpose | Reference |
| --- | --- | --- | --- |
| `TZ` | `env/common.example.env` | Ensures a consistent timezone for logs and schedules. | [env/README.md](../env/README.md#envcommonexampleenv) |
| `APP_DATA_DIR` / `APP_DATA_DIR_MOUNT` | `env/common.example.env` | Defines the persistent path (relative or absolute) used by the manifests. | [env/README.md](../env/README.md#envcommonexampleenv) |
| `APP_SHARED_DATA_VOLUME_NAME` | `env/common.example.env` | Standardizes the shared volume across multiple applications. | [env/README.md](../env/README.md#envcommonexampleenv) |
| `COMPOSE_EXTRA_FILES` | `env/<instance>.example.env` | Lists additional overlays applied after the default manifests. | [env/README.md](../env/README.md#como-gerar-arquivos-locais) |

> Use the [complete environment variables guide](../env/README.md) to review the latest list and document new fields. Example app and worker placeholders (such as `APP_SECRET`, `APP_RETENTION_HOURS`, and `WORKER_QUEUE_URL`) are detailed in the corresponding section of the [environment README](../env/README.md#placeholders-app-worker).

## Inspection tool

Run `scripts/describe_instance.sh <instance>` to audit the loaded manifests, active services, exposed ports, and resulting volumes from `docker compose config`. The `--list` flag reveals available instances, and `--format json` exports the metadata for automation.
