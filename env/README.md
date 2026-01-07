# Environment variables guide

This directory stores templates (`*.example.env`) and instructions for generating local files in `env/local/`. Derived repositories should adapt these examples to their service set while keeping the documentation up to date.

## How to generate local files

1. Create the Git-ignored directory:
   ```bash
   mkdir -p env/local
   ```
2. Copy the shared template to serve as the global base:
   ```bash
   cp env/common.example.env env/local/common.env
   ```
3. Copy the templates specific to each instance you will use:
   ```bash
   cp env/<target>.example.env env/local/<target>.env
   ```
4. Fill in the values according to the environment (development, lab, production, etc.).

> **Tip:** variables defined in `env/local/common.env` load before the instances (e.g., `env/local/core.env`). Use this file to consolidate shared credentials, timezone, volume UID/GID, and other global defaults.

## Variable mapping

### `env/common.example.env`

#### Base template variables

| Variable | Required? | Usage | Reference |
| --- | --- | --- | --- |
| `TZ` | Yes | Sets timezone for logs and schedules. | `docker-compose.<instance>.yml`. |
| `APP_DATA_DIR`/`APP_DATA_DIR_MOUNT` | Optional | Defines the relative persistent directory (`data/<instance>/<app>`) or an alternative absolute path—never use both at the same time. | `scripts/deploy_instance.sh`, `scripts/backup.sh`, `scripts/fix_permission_issues.sh`. |
| `APP_DATA_UID`/`APP_DATA_GID` | Optional | Adjusts the default owner of persistent volumes. | `scripts/deploy_instance.sh`, `scripts/backup.sh`, `scripts/fix_permission_issues.sh`. |
| `APP_NETWORK_NAME` | Optional | Logical name of the network shared among applications. | `compose/docker-compose.base.yml`. |
| `APP_NETWORK_DRIVER` | Optional | Driver used when creating the shared network (e.g., `bridge`, `macvlan`). | `compose/docker-compose.base.yml`. |
| `APP_NETWORK_SUBNET` | Optional | Subnet reserved for internal services. | `compose/docker-compose.base.yml`. |
| `APP_NETWORK_GATEWAY` | Optional | Gateway available to containers in the subnet above. | `compose/docker-compose.base.yml`. |
| `APP_SHARED_DATA_VOLUME_NAME` | Optional | Customizes the persistent volume shared between applications. | `compose/docker-compose.base.yml`. |

<a id="placeholders-app-worker"></a>

#### Example service placeholders (`app`/`worker`)

| Variable | Required? | Usage | Reference |
| --- | --- | --- | --- |
| `APP_SECRET` | Yes | Key used to encrypt sensitive data. | `docker-compose.<instance>.yml`. |
| `APP_RETENTION_HOURS` | Optional | Controls retention of records/processes. | `docker-compose.<instance>.yml` and runbooks. |
| `WORKER_QUEUE_URL` | Optional | Source queue processed by the example workers. | `docker-compose.<instance>.yml`. |

> When adapting the stack, rename or remove these placeholders to reflect your services’ real names and adjust the corresponding compose files (`docker-compose.<instance>.yml`). Keeping the generic `APP_*` names helps explain the template, but forks should align naming with the project domain (for example, `PORTAL_SECRET`, `PORTAL_RETENTION_HOURS`, `PAYMENTS_QUEUE_URL`).

Create a table similar to the one below for each `env/<target>.example.env` file:

| Variable | Required? | Usage | Reference |
| --- | --- | --- | --- |
| `APP_PUBLIC_URL` | Optional | Sets the public URL for links and cookies. | `docker-compose.<instance>.yml` (e.g., `docker-compose.core.yml`). |

> Replace the table with the real fields in your stack. Use the **Reference** column to point where the variable is consumed (manifests, scripts, external infrastructure, etc.).

The instance templates include illustrative placeholders that should be renamed according to each fork’s real service. Use the following list as a guide when reviewing `env/core.example.env` and `env/media.example.env`:

- `APP_PUBLIC_URL` and `APP_WEBHOOK_URL` — URLs injected into the main application (see service blocks in `docker-compose.<instance>.yml`).
- `APP_CORE_PORT` and `APP_MEDIA_PORT` — port mappings exposed by the instance compose files (`docker-compose.core.yml` and `docker-compose.media.yml`).
- `APP_NETWORK_IPV4` — static address used by the main service on internal networks (declared alongside the service in `docker-compose.<instance>.yml`).
- `MONITORING_NETWORK_IPV4` — IP reserved for the example monitoring service (declared in the monitoring service block of `docker-compose.<instance>.yml`).
- `WORKER_CORE_CONCURRENCY`, `WORKER_MEDIA_CONCURRENCY`, `WORKER_CORE_NETWORK_IPV4`, and `WORKER_MEDIA_NETWORK_IPV4` — variables consumed by the worker service definitions in the instance compose files.
- `CORE_PROXY_NETWORK_NAME`, `CORE_PROXY_IPV4`, and `CORE_LOGS_VOLUME_NAME` — shared resources defined in the `core` instance (`docker-compose.core.yml`).
- `MEDIA_HOST_PATH` and `MEDIA_CACHE_VOLUME_NAME` — mounts and volumes specific to the `media` instance (`docker-compose.media.yml`).

Rename these identifiers to terms aligned with your domain (for example, `PORTAL_PUBLIC_URL`, `PORTAL_NETWORK_IPV4`, `ACME_PROXY_NETWORK_NAME`) and update the associated manifests to avoid leftover default values.

> **Note:** the main persistent directory follows the `data/<instance>/<app>` convention using the primary service slug for the stack. Leave `APP_DATA_DIR` and `APP_DATA_DIR_MOUNT` blank to automatically use this relative fallback. Provide **only one** of them when you need to customize the path (relative or absolute, respectively); the scripts error out if both are set at the same time. Adjust `APP_DATA_UID` and `APP_DATA_GID` to align permissions.

> **New flow (`LOCAL_INSTANCE`)**: the wrappers (such as `scripts/deploy_instance.sh`) automatically export `LOCAL_INSTANCE` based on the `.env` file for the active instance (e.g., `core`, `media`). This variable injects the instance segment into the fallback `data/<instance>/<app>` used by the manifests. When running `docker compose` directly, export `LOCAL_INSTANCE=<instance>` before the command or reuse the scripts to avoid directory mismatches.

## Best practices

- **Standardize names:** use prefixes (`APP_`, `DB_`, `CACHE_`) to group responsibilities.
- **Document safe defaults:** indicate recommended values or expected formats (e.g., full URLs, keys with minimum length).
- **Keep secrets out of Git:** store only templates and documentation. Files in `env/local/` should be listed in `.gitignore`.
- **Sync with ADRs:** when new variables come from architectural decisions, reference the corresponding ADR in the table.

## Integration with scripts

Template scripts honor `COMPOSE_ENV_FILES` (and repeated `--env-file` flags) to select which `.env` files will be used, layering them on top of the default `env/local/common.env` → `env/local/<instance>.env` chain. Document in the relevant runbook how to combine variables and manifests for each environment. When multiple `.env` files are loaded (global + specific), the values defined last take precedence.
