# Template structure

> See the [main index](./README.md) and adjust this document whenever you create or remove structural components.

This guide describes the minimum structure expected for any repository inheriting this template. It ensures scripts, documentation, and pipelines can locate resources predictably.

## Required directories

> Single source of truth for the minimum directories the template requires. Always update this table before replicating changes into other documents.

| Path | Description | Expected items |
| --- | --- | --- |
| `compose/` | Base Docker Compose manifests and variations by environment or function. | `base.yml` (when necessary), named overlays (`<target>.yml`, e.g., [`core.yml`](../compose/core.yml) and [`media.yml`](../compose/media.yml), when they exist) and directories under `compose/apps/`. |
| `docs/` | Local documentation, runbooks, operational guides, and ADRs. | `README.md`, `STRUCTURE.md`, `OPERATIONS.md`, themed subfolders, and [`local/`](./local/README.md). |
| `env/` | Variable templates, example files, and fill-in instructions. | `*.example.env`, `README.md`, Git-ignored `local/`. Expand with variables needed for every enabled application. |
| `scripts/` | Reusable automation (deploy, validation, backups, health checks). | Shell scripts (or equivalents) referenced by the documentation. |
| `tests/` | Automated checks from the template that forks must preserve. | Base template tests; scenario-specific suites can live in dedicated directories outside `tests/`, as noted in [`tests/README.md`](../tests/README.md). |
| `.github/workflows/` | CI pipelines that guarantee the template’s minimum quality. | `template-quality.yml` (kept in line with the template) and any additional workflows required for the derived stack. |

> The utilities `scripts/check_structure.sh` and the suite `tests/test_check_structure.py` explicitly verify the presence of this directory and the `template-quality.yml` file. If any item is missing, the automated flow fails.

## Reference files

| Path | Purpose |
| --- | --- |
| `README.md` | Presents the derived repository, stack context, and links to local documentation. |
| `docs/STRUCTURE.md` | Keeps this description up to date as new components are added. |
| `docs/OPERATIONS.md` | Documents how to execute scripts and operational flows for the project. |
| `docs/ADR/` | Collects architectural decisions. Each file must follow the `YYYY-sequence-title.md` convention. |

## Per-application components

Each additional application must follow the pattern below to stay compatible with the template’s scripts and runbooks:

> Tip: use `scripts/bootstrap_instance.sh <app> <instance>` to automatically generate the files listed in the table below before customizing them. For applications composed only of overrides, add `--override-only` or let the script detect existing directories without `base.yml`.

| Path | Required? | Description |
| --- | --- | --- |
| `compose/apps/<app>/` | Yes | Dedicated directory containing the application manifests. |
| `compose/apps/<app>/base.yml` | When applicable | Base services reusable across every instance. Optional for applications composed only of instance-specific overrides. |
| `compose/apps/<app>/<instance>.yml` | One per instance | Override with service names, ports, and instance-specific variables. |
| `docs/apps/<app>.md` | Recommended | Support document describing the application’s responsibilities and requirements. |
| `env/<instance>.example.env` | One per instance | Must include every variable consumed by the manifests of the applications enabled for the instance. |

> For applications composed only of overrides, ensure the `<instance>.yml` files are present and follow the guidance in [Override-only applications](./COMPOSE_GUIDE.md#applications-composed-only-of-overrides).

## Suggested validations

1. **Structure** — reuse `scripts/check_structure.sh` to confirm required directories are present.
2. **Compose** — adapt `scripts/validate_compose.sh` (or equivalent) to validate manifests before merges/deploys.
3. **Helper scripts** — document in the `README.md` any additional tooling needed (for example, `make`, `poetry`, `ansible`).

## Keeping the template alive

- Update this page whenever you rename directories or introduce new required conventions.
- Review PRs in derived projects to ensure essential directories stay aligned with the template.
- Record intentional deviations in ADRs or the customization guide to ease future audits.
