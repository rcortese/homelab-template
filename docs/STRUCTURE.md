# Template structure

> See the [main index](./README.md) and adjust this document whenever you create or remove structural components.

This guide describes the minimum structure expected for any repository inheriting this template. It ensures scripts, documentation, and pipelines can locate resources predictably.

## Required directories

> Single source of truth for the minimum directories the template requires. Always update this table before replicating changes into other documents.

| Path | Description | Expected items |
| --- | --- | --- |
| `compose/` | Base Docker Compose anchors and instance compose files. | `docker-compose.base.yml` (when necessary) plus `docker-compose.<instance>.yml` for each instance. |
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

## Instance components

Each instance is defined by a consolidated compose file and its supporting documentation/configuration:

| Path | Required? | Description |
| --- | --- | --- |
| `compose/docker-compose.<instance>.yml` | Yes (one per instance) | Complete compose file for the instance (services, networks, volumes, labels, and profiles). |
| `compose/docker-compose.base.yml` | Optional | Anchors and shared resources loaded before any instance file. |
| `COMPOSE_EXTRA_FILES` | Optional | Additional compose files appended after the instance file for experiments or environment-specific tuning. |
| `docs/apps/<component>.md` | Recommended | Support document describing the responsibilities and requirements of key services or components. |
| `env/<instance>.example.env` | One per instance | Must include every variable consumed by the services enabled for the instance. |

## Suggested validations

1. **Structure** — reuse `scripts/check_structure.sh` to confirm required directories are present.
2. **Compose** — adapt `scripts/validate_compose.sh` (or equivalent) to validate manifests before merges/deploys.
3. **Helper scripts** — document in the `README.md` any additional tooling needed (for example, `make`, `poetry`, `ansible`).

## Keeping the template alive

- Update this page whenever you rename directories or introduce new required conventions.
- Review PRs in derived projects to ensure essential directories stay aligned with the template.
- Record intentional deviations in ADRs or the customization guide to ease future audits.
