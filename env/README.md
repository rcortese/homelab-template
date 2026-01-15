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
| `APP_EXAMPLE_MESSAGE` | Optional | Placeholder message passed into the example app container. | `compose/docker-compose.common.yml`. |

<a id="placeholders-app-worker"></a>

#### Example service placeholders (`app`)

| Variable | Required? | Usage | Reference |
| --- | --- | --- | --- |
| `APP_EXAMPLE_MESSAGE` | Optional | Placeholder value injected into the example app. | `compose/docker-compose.common.yml`. |

> When adapting the stack, rename or remove the placeholder above to reflect your services’ real names and adjust the corresponding compose files (`compose/docker-compose.common.yml`). Keeping the generic `APP_*` name helps explain the template, but forks should align naming with the project domain (for example, `PORTAL_GREETING`).

Create a table similar to the one below for each `env/<target>.example.env` file.

### `env/core.example.env`

| Variable | Required? | Usage | Reference |
| --- | --- | --- | --- |
| `APP_PORT` | Optional | Host port mapped to the app container. | `compose/docker-compose.core.yml`. |

### `env/media.example.env`

| Variable | Required? | Usage | Reference |
| --- | --- | --- | --- |
| `APP_PORT` | Optional | Host port mapped to the app container. | `compose/docker-compose.media.yml`. |

Create a table for any additional `env/<target>.example.env` file and document only the variables present in that instance's compose manifests. Use the **Reference** column to point where the variable is consumed (manifests, scripts, external infrastructure, etc.).

`REPO_ROOT` is derived by the scripts and written to the generated root `.env`, so it should not appear in `env/*.example.env` or `env/local/*.env`.

The instance templates include illustrative placeholders that should be renamed according to each fork’s real service. Use the following list as a guide when reviewing `env/common.example.env`, `env/core.example.env`, and `env/media.example.env`:

- `APP_EXAMPLE_MESSAGE` — placeholder message passed into the example app (`compose/docker-compose.common.yml`).
- `APP_PORT` — host port mapping for the example app (`compose/docker-compose.core.yml` and `compose/docker-compose.media.yml`).

Rename these identifiers to terms aligned with your domain (for example, `PORTAL_GREETING`, `PORTAL_PORT`) and update the associated manifests to avoid leftover default values.

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
