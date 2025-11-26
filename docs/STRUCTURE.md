# Template structure

> See the [documentation index](./README.md) and update this page whenever you create or remove structural components.

This guide describes the minimum structure expected for any repository inheriting this template. It ensures scripts, documentation, and pipelines can locate resources predictably.

## Required directories

> Single source of truth for the minimum directories the template requires. Always update this table before replicating changes elsewhere.

| Path | Description | Expected items |
| --- | --- | --- |
| `compose/` | Base Docker Compose manifests and environment- or role-specific variations. | `base.yml` (when needed), named overlays (`<target>.yml`, e.g., [`core.yml`](../compose/core.yml) and [`media.yml`](../compose/media.yml), when present) and directories in `compose/apps/`. |
| `docs/` | Local documentation, runbooks, operational guides, and ADRs. | `README.md`, `STRUCTURE.md`, `OPERATIONS.md`, thematic subfolders, and [`local/`](./local/README.md). |
| `env/` | Variable templates, example files, and filling instructions. | `*.example.env`, `README.md`, `local/` ignored by Git. Expand with variables required for all enabled applications. |
| `scripts/` | Reusable automation (deploy, validation, backups, health checks). | Shell scripts (or equivalents) referenced by the documentation. |
| `tests/` | Automated checks from the template that should be preserved in forks. | Base template tests; specific scenarios can live in dedicated directories outside `tests/`, as indicated in [`tests/README.md`](../tests/README.md). |
| `.github/workflows/` | CI pipelines that guarantee the template’s minimum quality bar. | `template-quality.yml` (kept per the template) and additional workflows needed for the derived stack. |

> The utilities `scripts/check_structure.sh` and the `tests/test_check_structure.py` suite explicitly verify the presence of this directory and the `template-quality.yml` file. If any item is missing, the automated flow fails.

## Reference files

| Path | Purpose |
| --- | --- |
| `README.md` | Presents the derived repository, stack context, and links to local documentation. |
| `docs/STRUCTURE.md` | Maintains this description as new components are added. |
| `docs/OPERATIONS.md` | Documents how to run scripts and operational flows for the project. |
| `docs/ADR/` | Collects architectural decisions. Each file must follow the `YYYY-sequence-title.md` convention. |

## Components per application

Each additional application must follow the structure below to remain compatible with the template’s scripts and runbooks:

> Tip: use `scripts/bootstrap_instance.sh <app> <instance>` to generate the files listed in the table below before customizing them. For applications composed only of overrides, add `--override-only` or let the script detect existing directories without `base.yml`.

| Path | Required? | Description |
| --- | --- | --- |
| `compose/apps/<app>/` | Yes | Dedicated directory with the application manifests. |
| `compose/apps/<app>/base.yml` | When applicable | Base services reused by all instances. Optional for applications composed only of instance-specific overrides. |
| `compose/apps/<app>/<instance>.yml` | One per instance | Override with instance-specific service names, ports, and variables. |
| `docs/apps/<app>.md` | Recommended | Supporting document describing the application’s responsibilities and requirements. |
| `env/<instance>.example.env` | One per instance | Must include all variables consumed by the manifests of applications enabled for the instance. |

> For applications composed only of overrides, ensure the `<instance>.yml` files exist and follow the guidance in [Applications composed only of overrides](./COMPOSE_GUIDE.md#applications-composed-only-of-overrides).

## Suggested validations

1. **Structure** — reuse `scripts/check_structure.sh` to ensure required directories are present.
2. **Compose** — adapt `scripts/validate_compose.sh` (or equivalent) to validate manifests before merges/deploys.
3. **Helper scripts** — document in `README.md` any additional tooling required (e.g., `make`, `poetry`, `ansible`).

## Keeping the template healthy

- Update this page whenever directories are renamed or new mandatory conventions are introduced.
- Review PRs from derived projects to ensure essential directories stay aligned with the template.
- Record intentional deviations in ADRs or the customization guide to simplify future audits.
