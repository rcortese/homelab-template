# Environment variables guide

This directory stores templates (`*.example.env`) and instructions to generate local files under `env/local/`. Derived repositories should adapt these examples to their service set while keeping the documentation up to date.

## How to generate local files

1. Create the Git-ignored directory:
   ```bash
   mkdir -p env/local
   ```
2. Copy the shared template to use as a global base:
   ```bash
   cp env/common.example.env env/local/common.env
   ```
3. Copy the templates specific to each instance you will use:
   ```bash
   cp env/<target>.example.env env/local/<target>.env
   ```
4. Fill in the values according to the environment (development, lab, production, etc.).

> **Tip:** variables defined in `env/local/common.env` are loaded before the instances (e.g., `env/local/core.env`). Use this file to consolidate shared credentials, time zone, UID/GID for volumes, and other global defaults.

## Variable mapping

### `env/common.example.env`

#### Base template variables

| Variable | Required? | Purpose | Reference |
| --- | --- | --- | --- |
| `TZ` | Yes | Sets timezone for logs and schedules. | `compose/apps/app/base.yml`. |
| `APP_DATA_DIR`/`APP_DATA_DIR_MOUNT` | Optional | Defines the relative persistent directory (`data/<instance>/<app>`) or an alternate absolute path—never use both at the same time. | `scripts/deploy_instance.sh`, `scripts/compose.sh`, `scripts/backup.sh`, `scripts/fix_permission_issues.sh`. |
| `APP_DATA_UID`/`APP_DATA_GID` | Optional | Sets the default owner of persistent volumes. | `scripts/deploy_instance.sh`, `scripts/backup.sh`, `scripts/fix_permission_issues.sh`. |
| `APP_NETWORK_NAME` | Optional | Logical name of the network shared between applications. | `compose/base.yml`. |
| `APP_NETWORK_DRIVER` | Optional | Driver used when creating the shared network (e.g., `bridge`, `macvlan`). | `compose/base.yml`. |
| `APP_NETWORK_SUBNET` | Optional | Subnet reserved for internal services. | `compose/base.yml`. |
| `APP_NETWORK_GATEWAY` | Optional | Gateway provided to containers on the subnet above. | `compose/base.yml`. |
| `APP_SHARED_DATA_VOLUME_NAME` | Optional | Customizes the persistent volume shared between applications. | `compose/base.yml`. |

<a id="placeholders-app-worker"></a>

#### Example app/worker placeholders (`app`/`worker`)

| Variable | Required? | Purpose | Reference |
| --- | --- | --- | --- |
| `APP_SECRET` | Yes | Key used to encrypt sensitive data. | `compose/apps/app/base.yml`. |
| `APP_RETENTION_HOURS` | Optional | Controls record/process retention. | `compose/apps/app/base.yml` and runbooks. |
| `WORKER_QUEUE_URL` | Optional | Source of the task queue processed by the example workers. | `compose/apps/worker/base.yml`. |

> When adapting the stack, rename or remove these placeholders to reflect the real name of your applications and adjust the corresponding manifests (`compose/apps/<your-app>/` and `compose/apps/worker/`). Keeping the generic `APP_*` names helps understand the template, but forks should align naming with the project domain (for example, `PORTAL_SECRET`, `PORTAL_RETENTION_HOURS`, `PAYMENTS_QUEUE_URL`).

Create a table similar to the one below for each `env/<target>.example.env` file:

| Variable | Required? | Purpose | Reference |
| --- | --- | --- | --- |
| `APP_PUBLIC_URL` | Optional | Defines public URL for links and cookies. | `compose/apps/<app>/<instance>.yml` (e.g., `compose/apps/app/core.yml`). |
| `COMPOSE_EXTRA_FILES` | Optional | Lists additional overlays applied after the instance override (separated by space or comma). | `scripts/deploy_instance.sh`, `scripts/validate_compose.sh`, `scripts/lib/compose_defaults.sh`. |

> Replace the table with the real fields from your stack. Use the **Reference** column to point to where the variable is consumed (manifests, scripts, external infrastructure, etc.).

The instance templates include illustrative placeholders that should be renamed according to the real service of each fork. Use the following list as a guide when reviewing `env/core.example.env` and `env/media.example.env`:

- `APP_PUBLIC_URL` and `APP_WEBHOOK_URL` — URLs injected into the main application (`compose/apps/app/core.yml`).
- `APP_CORE_PORT` and `APP_MEDIA_PORT` — port mappings exposed by the instance-specific manifests (`compose/apps/app/core.yml` and `compose/apps/app/media.yml`).
- `APP_NETWORK_IPV4` — static address used by the main service on internal networks (`compose/apps/app/base.yml`).
- `MONITORING_NETWORK_IPV4` — IP reserved for the example monitoring service (`compose/apps/monitoring/base.yml` and `compose/apps/monitoring/core.yml`).
- `WORKER_CORE_CONCURRENCY`, `WORKER_MEDIA_CONCURRENCY`, `WORKER_CORE_NETWORK_IPV4`, and `WORKER_MEDIA_NETWORK_IPV4` — variables consumed by the worker manifests (`compose/apps/worker/core.yml` and `compose/apps/worker/media.yml`).
- `CORE_PROXY_NETWORK_NAME`, `CORE_PROXY_IPV4`, and `CORE_LOGS_VOLUME_NAME` — shared resources defined in the `core` instance (`compose/core.yml`).
- `MEDIA_HOST_PATH` and `MEDIA_CACHE_VOLUME_NAME` — mounts and volumes specific to the `media` instance (`compose/apps/app/media.yml` and `compose/media.yml`).

Rename these identifiers to terms aligned with your domain (for example, `PORTAL_PUBLIC_URL`, `PORTAL_NETWORK_IPV4`, `ACME_PROXY_NETWORK_NAME`) and update the associated manifests to avoid leftovers from the default example.

> **Note:** the main persistent directory follows the `data/<instance>/<app>` convention, considering the main application (first in the `COMPOSE_INSTANCE_APP_NAMES` list). Leave `APP_DATA_DIR` and `APP_DATA_DIR_MOUNT` blank to automatically use this relative fallback. Provide **only one** of them when you need to customize the path (relative or absolute, respectively); the scripts return an error if both are defined at the same time. Adjust `APP_DATA_UID` and `APP_DATA_GID` to align permissions.

> **New flow (`LOCAL_INSTANCE`)**: the wrappers (`scripts/compose.sh`, `scripts/deploy_instance.sh`, etc.) automatically export `LOCAL_INSTANCE` based on the `.env` file of the active instance (e.g., `core`, `media`). This variable injects the instance segment into the `data/<instance>/<app>` fallback used by the manifests. When running `docker compose` directly, export `LOCAL_INSTANCE=<instance>` before the command or reuse the scripts to avoid directory mismatches.

## Best practices

- **Standardize names:** use prefixes (`APP_`, `DB_`, `CACHE_`) to group responsibilities.
- **Document safe defaults:** indicate recommended values or expected formats (e.g., full URLs, keys with minimum size).
- **Avoid secrets in Git:** keep only templates and documentation. Files in `env/local/` must be listed in `.gitignore`.
- **Sync with ADRs:** if new variables are introduced by architectural decisions, reference the corresponding ADR in the table.

## Integration with scripts

The scripts provided by the template accept `COMPOSE_ENV_FILES` (or the legacy `COMPOSE_ENV_FILE`) to select which `.env` files will be used. Document, in the corresponding runbook, how to combine variables and manifests for each environment. When you need to enable specific overlays without modifying scripts, add something like this to `.env`:

```env
COMPOSE_EXTRA_FILES=compose/overlays/observability.yml compose/overlays/metrics.yml
```

This pattern keeps differences between template and fork confined to configuration files. When multiple `.env` files are loaded (global + specific), the values defined last take precedence.
