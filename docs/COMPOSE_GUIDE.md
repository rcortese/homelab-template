# Docker Compose combination guide

> Part of the [documentation index](./README.md). Read the [Overview](./OVERVIEW.md) to understand the role of each instance and align checklists with the runbooks for [core](./core.md) and [media](./media.md).

This guide documents how to build the Docker Compose plan using only the base file, the instance-wide override, and the manifests for each application. For a short view of the load order, see the [`compose/` README](../compose/README.md). Follow these instructions before running `docker compose`.

> **Attention for forks:** all `compose/...` paths here are examples. Adjust directory, file, and service names according to step 3 of [How to start a derived project](../README.md#how-to-start-a-derived-project) when adapting the template to your stack.

## Manifest structure

| File type | Location | Role |
| --------------- | ----------- | ----- |
| **Base** | `compose/base.yml` (optional) | Holds only anchors and shared volumes reused by applications. It is loaded automatically when present; if absent, the plan starts directly with the instance manifests. |
| **Instance (global)** | `compose/<instance>.yml` (e.g., [`compose/core.yml`](../compose/core.yml), [`compose/media.yml`](../compose/media.yml)) *(optional)* | Collects adjustments shared by every application in that instance (e.g., extra networks, default volumes, or global labels). When the file exists, it is applied immediately after the base manifest so resources are overridden before the application manifests. |
| **Application** | `compose/apps/<app>/base.yml` | Declares the additional services that compose an application (e.g., `app`). Uses anchors defined in `compose/base.yml`. Replace `<app>` with your main application directory (e.g., `compose/apps/<your-app>/base.yml`). It is included automatically for all instances **when the file exists**. |
| **Application overrides** | `compose/apps/<app>/<instance>.yml` | Specializes the application services per environment (container name, ports, instance-specific variables such as `APP_PUBLIC_URL` or `MEDIA_ROOT`). Each instance has one file per application (e.g., `compose/apps/<your-app>/core.yml`). |

> **Note:** applications with only `base.yml` are automatically loaded in **all** instances, including those without a dedicated override even if other instances already have their own overrides. To restrict execution to a specific subset, create an override per instance (even if the contents are just `profiles` or `deploy.replicas: 0`) or move the manifests into an override-only directory.

Example stub to disable an application on the `media` instance:

1. Create the file `compose/apps/<app>/media.yml` (replace `<app>` with the application directory).
2. Insert only the fields needed to adjust the target service, as in the example below, setting `deploy.replicas: 0`:

```yaml
# compose/apps/<app>/media.yml
services:
  <main-service>:
    deploy:
      replicas: 0
```

> Adjust `<main-service>` to the service name declared in `compose/apps/<app>/base.yml`. This stub keeps the service active in the other instances (with their own overrides) and disables it only in `media`.

### Examples included in the template

- When present, [`compose/core.yml`](../compose/core.yml) documents how to add reverse proxy labels, connect instance services to an external network (`core_proxy`), and declare named volumes (`core_logs`).
- When present, [`compose/media.yml`](../compose/media.yml) shows how to share media mounts (`MEDIA_HOST_PATH`) between services and how to define a common volume for transcoding caches (`media_cache`).

### Applications composed only of overrides

Not every application needs a `base.yml`. Some stacks reuse existing services and apply only instance-specific adjustments (for example, adding labels, extra networks, or variables). In these cases, the application directory is considered **override-only**.

#### How to prepare the directory

1. Create the directory `compose/apps/<app>/` as usual.
2. Add at least one file `compose/apps/<app>/<instance>.yml` with the services and adjustments for that instance.
3. Omitting `compose/apps/<app>/base.yml` is fine. Whenever the directory lacks that file, the scripts automatically treat the application as override-only and do not try to attach a missing manifest to the plan.

#### Automatic generation with `bootstrap_instance`

Use `scripts/bootstrap_instance.sh <app> <instance> --override-only` to generate only the override and variable file when building an application without `base.yml`. If the application directory already exists without a base file, the script detects override-only mode automatically when adding new instances, avoiding redundant artifacts.

#### How the scripts handle pure overrides

- `scripts/lib/compose_discovery.sh` identifies override-only directories and records only the existing `<instance>.yml` files.
- During plan generation (`scripts/lib/compose_plan.sh`), only those overrides are chained after `compose/base.yml` (when present) and the instance-wide adjustments, preserving the order of the other manifests.
- The map `COMPOSE_APP_BASE_FILES`, exported by `scripts/lib/compose_instances.sh`, keeps only applications with a real `base.yml`. Override-only directories stay out of this map and therefore do not introduce broken references in validations or `docker compose` commands.

## Stacks with multiple applications

When combining several applications, load the manifests in blocks (`base.yml`, application `base.yml`, and the instance override) in the order shown below. This ensures anchors and variables are available before the services that consume them.

| Order | File | Purpose |
| ----- | ------- | ------ |
| 1 | `compose/base.yml` (when present) | Foundational structure with shared anchors. |
| 2 | `compose/<instance>.yml` (e.g., `compose/core.yml`, `compose/media.yml`) *(when present)* | Global adjustments for the instance (labels, extra networks, default policies). |
| 3 | `compose/apps/<main-app>/base.yml` (e.g., `compose/apps/app/base.yml`) | Defines the main application services. |
| 4 | `compose/apps/<main-app>/<instance>.yml` (e.g., `compose/apps/app/core.yml`) | Adjusts the main application for the target instance. |
| 5 | `compose/apps/<aux-app>/base.yml` (e.g., `compose/apps/monitoring/base.yml`) | Declares auxiliary services (e.g., observability). |
| 6 | `compose/apps/<aux-app>/<instance>.yml` (e.g., `compose/apps/monitoring/core.yml`) | Customizes auxiliary services for the instance. |
| 7 | `compose/apps/<other-app>/base.yml` (e.g., `compose/apps/worker/base.yml`) | Introduces asynchronous workers that depend on the main application. |
| 8 | `compose/apps/<other-app>/<instance>.yml` (e.g., `compose/apps/worker/core.yml`) | Adjusts worker name/concurrency per instance. |
| 9 | `compose/apps/<another-app>/...` | Repeat the pattern for each extra application. |

> If an application does not have `base.yml`, skip the corresponding step and keep only the override (`compose/apps/<app>/<instance>.yml`). The template scripts make this adjustment automatically when generating the plan.

> **Replace the placeholders:** `app`, `monitoring`, `worker`, and any other names used in the tables and examples are merely illustrative directory names. Align each occurrence with the real application name following step 3 of [How to start a derived project](../README.md#how-to-start-a-derived-project).

### Base snippet to combine manifests

Use the skeleton below for any instance, filling in the `<instance>` placeholder and adding only the desired applications. When you need extra overlays (e.g., `compose/overlays/metrics.yml`), list them in the `COMPOSE_EXTRA_FILES` variable separated by spaces before running the command. The snippet automatically converts each entry into a new `-f`.

```bash
docker compose \
  --env-file env/local/common.env \
  --env-file env/local/<instance>.env \
  -f compose/base.yml \  # Include only if the file exists
  -f compose/<instance>.yml \ # Include only if the file exists (e.g., compose/core.yml)
  -f compose/apps/<main-app>/base.yml \
  -f compose/apps/<main-app>/<instance>.yml \
  # Optional: add base/instance pairs for each enabled auxiliary application
  -f compose/apps/<optional-app>/base.yml \
  -f compose/apps/<optional-app>/<instance>.yml \
  $(for file in ${COMPOSE_EXTRA_FILES:-}; do printf ' -f %s' "$file"; done) \
  up -d
```

> Example: replace `<main-app>` with your real application directory (such as `compose/apps/app/`). Keep names and paths in sync with step 3 of [How to start a derived project](../README.md#how-to-start-a-derived-project) to avoid stale references after renaming services.

> `COMPOSE_EXTRA_FILES` should contain additional overlays (e.g., files under `compose/overlays/`) listed in order. Set the variable with `export` or inline (`COMPOSE_EXTRA_FILES="compose/overlays/metrics.yml" docker compose ...`) to attach the extra manifests to the stack.

#### How to enable or disable auxiliary applications

- **Keep enabled**: keep the matching `base.yml`/`<instance>.yml` pair in the snippet (e.g., `monitoring` → `-f compose/apps/monitoring/base.yml` + `-f compose/apps/monitoring/<instance>.yml`).
- **Disable selectively**: keep an explicit override for each instance where the service should be off (e.g., `compose/apps/monitoring/media.yml` with `deploy.replicas: 0` or specific `profiles`). This approach ensures the scripts continue to load the application only where it is enabled and prevents accidental activation in new instances.
- **Remove globally**: delete the pair of lines when the application no longer belongs in **any** instance.
- **Add another application**: duplicate the two lines, replacing `<optional-app>` with the directory under `compose/apps/<app>/`.

> **Important:** when running Compose manually, mirror the same chain of `.env` files used by the scripts (`env/local/common.env` followed by `env/local/<instance>.env`). See the walkthrough in [`env/README.md#como-gerar-arquivos-locais`](../env/README.md#como-gerar-arquivos-locais) to ensure required global variables are not omitted. Also, export `LOCAL_INSTANCE=<instance>` (the wrapper does this automatically) before calling `docker compose` to preserve the `data/<instance>/<app>` path in the volumes.

The differences between the main instances are concentrated in the files loaded and the variables referenced by the command above:

| Scenario | `--env-file` (order) | Required overrides (`-f`) | Additional overlays | Notes |
| ------- | -------------------- | ----------------------------- | ------------------- | ----------- |
| **core** | `env/local/common.env` → `env/local/core.env` | `compose/core.yml` (when present), `compose/apps/<main-app>/core.yml` (e.g., `compose/apps/app/core.yml`) | — | No required overlays. Use them only when the stack demands extra files. |
| **media** | `env/local/common.env` → `env/local/media.env` | `compose/media.yml` (when present), `compose/apps/<main-app>/media.yml` (e.g., `compose/apps/app/media.yml`) | Optional: `compose/overlays/<overlay>.yml` (e.g., media storage) | Add instance-specific overlays by listing them in `COMPOSE_EXTRA_FILES` before running the command. |

### Ad-hoc combination with `COMPOSE_FILES`

```bash
export COMPOSE_FILES="compose/base.yml compose/media.yml compose/apps/<main-app>/base.yml compose/apps/<main-app>/media.yml" # Remove missing entries
docker compose \
  --env-file env/local/common.env \
  --env-file env/local/media.env \
  $(for file in $COMPOSE_FILES; do printf ' -f %s' "$file"; done) \
  up -d
```

> Adjust `<main-app>` to your application directory (e.g., `compose/apps/app/`). Aligning manifests with step 3 of [How to start a derived project](../README.md#how-to-start-a-derived-project) avoids outdated paths after renaming services.

### Generating an instance summary

Use `scripts/describe_instance.sh` to quickly inspect the applied manifests, resulting services, published ports, and mounted volumes. The script reuses the same `-f` planning as the deploy and validation flows and marks additional overlays loaded via `COMPOSE_EXTRA_FILES`.

```bash
scripts/describe_instance.sh core

scripts/describe_instance.sh media --format json
```

The default `table` format helps manual reviews, while `--format json` is ideal for automated documentation or feeding dashboards.

Example (`table` format):

> The `compose/apps/app/` directory below is illustrative. Adapt it to the name of your main application and validate the manifests according to step 3 of [How to start a derived project](../README.md#how-to-start-a-derived-project).

```
Instance: core

Compose files (-f):
  • compose/base.yml
  • compose/core.yml
  • compose/apps/app/base.yml
  • compose/apps/app/core.yml
  • compose/overlays/metrics.yml (extra overlay)

Extra overlays applied:
  • compose/overlays/metrics.yml

Services:
  - app
      Published ports:
        • 8080 -> 80/tcp
      Mounted volumes:
        • /srv/app/data -> /data/app (type=bind)
```

## Best practices

> Align any `compose/...` path mentioned below with step 3 of [How to start a derived project](../README.md#how-to-start-a-derived-project) whenever you rename applications or instances in your fork.

- Always load `compose/base.yml` first.
- When it exists, apply `compose/<instance>.yml` immediately after the base file.
- Include `compose/apps/<app>/base.yml` before the per-instance overrides **when they exist**.
- Chain the override `compose/apps/<app>/<instance>.yml` right after the application's `base.yml`.
- Keep the file combination in sync with the environment variable chain (`env/local/common.env` → `env/local/<instance>.env`).
- Re-validate combinations with [`scripts/validate_compose.sh`](./OPERATIONS.md#scriptsvalidate_compose.sh) when any file in `compose/` changes.
