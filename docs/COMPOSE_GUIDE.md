# Docker Compose combination guide

> Part of the [documentation index](./README.md). Read the [Overview](./OVERVIEW.md) to understand the role of each instance and align checklists with the runbooks for [core](./core.md) and [media](./media.md).

This guide documents how to build the Docker Compose plan using only the base file, the instance-wide override, and the manifests for each application. For a short view of the load order, see the [`compose/` README](../compose/README.md). Follow these instructions before running the generator that writes `docker-compose.yml` to the repository root.

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

### Default flow with the generated `docker-compose.yml`

1. Generate the consolidated file with the new generator:

   ```bash
   scripts/build_compose_file.sh --instance <instance> \
     --file compose/overlays/<overlay>.yml \      # optional, repeat if you need more than one
     --env-file env/local/common.env \             # optional override for the default chain
     --env-file env/local/<instance>.env           # optional instance override
   ```

   - Additional `--file` flags replace the previous use of `COMPOSE_EXTRA_FILES` when appending temporary overlays.
   - `--env-file` keeps the legacy order (`common` → `<instance>`) and accepts alternative chains when you need to test specific variables without touching the files under `env/local/`.
   - Re-run the command whenever manifests (`compose/...`) or variables (`env/...`) change to refresh the root `docker-compose.yml`.

2. Use the generated file directly to start or inspect services:

   ```bash
   docker compose up -d
   docker compose ps
   ```

   The default command now targets the root `docker-compose.yml`, avoiding manual `-f` assembly and `--env-file` chains.
   This consolidated-file workflow is the supported path for running Compose commands and replaces earlier compatibility modes.

> Set `<instance>` to `core`, `media`, or any other name defined in your fork. Replace `<overlay>` with real files under `compose/overlays/` whenever you need temporary or environment-specific adjustments.

#### How to enable or disable auxiliary applications

- **Keep enabled**: ensure the application directory includes the `base.yml`/`<instance>.yml` pair. The generator automatically builds the sequence in the correct order.
- **Disable selectively**: keep an explicit override for each instance where the service must stay off (for example, `compose/apps/monitoring/media.yml` with `deploy.replicas: 0`). This prevents accidental activations when adding new instances.
- **Remove globally**: delete the `base.yml`/`<instance>.yml` pair when the application is no longer part of **any** instance.
- **Add another application**: create the manifest pairs under `compose/apps/<app>/`. The generator detects the directories and includes the files according to the discovered plan.

> Whenever you update an application's manifests or the variable chain, regenerate `docker-compose.yml` before calling `docker compose up -d` to avoid divergence between the plan and the consolidated file.

### Generating an instance summary

Use `scripts/describe_instance.sh` to quickly inspect the applied manifests, resulting services, published ports, and mounted volumes. The script reuses the same planning chain as the deploy and validation flows and marks additional overlays loaded via `COMPOSE_EXTRA_FILES` or provided with `--file` in the generator.

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
