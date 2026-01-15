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
| `APP_DATA_UID`/`APP_DATA_GID` | Optional | Adjusts the default owner of persistent volumes. | `scripts/deploy_instance.sh`, `scripts/backup.sh`, `scripts/fix_permission_issues.sh`. |
| `APP_NETWORK_NAME` | Optional | Logical name of the network shared among applications. | `compose/docker-compose.common.yml`. |
| `APP_NETWORK_DRIVER` | Optional | Driver used when creating the shared network (e.g., `bridge`, `macvlan`). | `compose/docker-compose.common.yml`. |
| `APP_NETWORK_SUBNET` | Optional | Subnet reserved for internal services. | `compose/docker-compose.common.yml`. |
| `APP_NETWORK_GATEWAY` | Optional | Gateway available to containers in the subnet above. | `compose/docker-compose.common.yml`. |
| `APP_SHARED_DATA_VOLUME_NAME` | Optional | Customizes the persistent volume shared between applications. | `compose/docker-compose.common.yml`. |

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
| `COMPOSE_EXTRA_FILES` | Optional | Lists additional compose files applied after the instance override (space- or comma-separated). | `scripts/deploy_instance.sh`, `scripts/validate_compose.sh`, `scripts/_internal/lib/compose_defaults.sh`. |

> Replace the table with the real fields in your stack. Use the **Reference** column to point where the variable is consumed (manifests, scripts, external infrastructure, etc.).

`REPO_ROOT` is derived by the scripts and written to the generated root `.env`, so it should not appear in `env/*.example.env` or `env/local/*.env`.

The instance templates include illustrative placeholders that should be renamed according to each fork’s real service. Use the following list as a guide when reviewing `env/core.example.env` and `env/media.example.env`:

- `APP_PUBLIC_URL` and `APP_WEBHOOK_URL` — URLs injected into the main application (see service blocks in `docker-compose.<instance>.yml`).
- `APP_CORE_PORT` and `APP_MEDIA_PORT` — port mappings exposed by the instance compose files (`docker-compose.core.yml` and `docker-compose.media.yml`).
- `APP_NETWORK_IPV4` — static address used by the main service on internal networks (declared alongside the service in `docker-compose.<instance>.yml`).
- `MONITORING_NETWORK_IPV4` — IP reserved for the example monitoring service (declared in the monitoring service block of `docker-compose.<instance>.yml`).
- `WORKER_CORE_CONCURRENCY`, `WORKER_MEDIA_CONCURRENCY`, `WORKER_CORE_NETWORK_IPV4`, and `WORKER_MEDIA_NETWORK_IPV4` — variables consumed by the worker service definitions in the instance compose files.
- `CORE_PROXY_NETWORK_NAME`, `CORE_PROXY_IPV4`, and `CORE_LOGS_VOLUME_NAME` — shared resources defined in the `core` instance (`docker-compose.core.yml`).
- `MEDIA_HOST_PATH` and `MEDIA_CACHE_VOLUME_NAME` — mounts and volumes specific to the `media` instance (`docker-compose.media.yml`).

Rename these identifiers to terms aligned with your domain (for example, `PORTAL_PUBLIC_URL`, `PORTAL_NETWORK_IPV4`, `ACME_PROXY_NETWORK_NAME`) and update the associated manifests to avoid leftover default values.

> **Note:** the main persistent directory follows the `data/<instance>/app` convention relative to the repository root. Scripts derive `REPO_ROOT` at runtime and write it to the generated root `.env` so Compose can resolve persistent mounts. Adjust `APP_DATA_UID` and `APP_DATA_GID` to align permissions.

> **`LOCAL_INSTANCE` flow:** the wrappers (such as `scripts/deploy_instance.sh`) derive `LOCAL_INSTANCE` based on the selected instance (e.g., `core`, `media`) and write it into the generated `.env`. Use the scripts or the generated `.env` when running `docker compose` so the manifests receive the correct instance name.

## Best practices

- **Standardize names:** use prefixes (`APP_`, `DB_`, `CACHE_`) to group responsibilities.
- **Document safe defaults:** indicate recommended values or expected formats (e.g., full URLs, keys with minimum length).
- **Keep secrets out of Git:** store only templates and documentation. Files in `env/local/` should be listed in `.gitignore`.
- **Sync with ADRs:** when new variables come from architectural decisions, reference the corresponding ADR in the table.

## Integration with scripts

Template scripts honor `COMPOSE_ENV_FILES` (and repeated `--env-file` flags) to append extra `.env` files after the default `env/local/common.env` → `env/local/<instance>.env` chain. To fully replace the defaults, set `COMPOSE_ENV_CHAIN` (or use `--env-chain` with `scripts/build_compose_file.sh`) and list the explicit chain. Document in the relevant runbook how to combine variables and manifests for each environment. When you need to enable specific compose files without changing scripts, set `COMPOSE_EXTRA_FILES` in `env/local/common.env` or `env/local/<instance>.env` (not the generated root `.env`):

```env
COMPOSE_EXTRA_FILES=compose/extra/observability.yml compose/extra/metrics.yml
```

This pattern keeps differences between the template and the fork confined to configuration files. When multiple `.env` files are loaded (global + specific), the values defined last take precedence.
