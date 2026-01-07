# Template documentation index

> Use this index as a starting point to customize the template. Begin with the [main README](../README.md) to understand the overall purpose.

The documents below remain generic to ease merges from the template. To record specific adaptations, use [`docs/local/`](./local/README.md) and reference those materials only when needed.

## Getting started

- [Onboarding guide](./ONBOARDING.md) — Summary of the initial flow with prerequisites, `env/local` bootstrap, and required validations.
- [Template structure](./STRUCTURE.md) — Mandatory directory conventions, essential files, and validations. The directory table there is the single source of truth for the minimum structure.
- [Environment variables guide](../env/README.md) — How to map and document variables across environments.

## Overview and integrations

- [Stack overview](./OVERVIEW.md) — Customize this panorama to reflect your fork’s context and keep it updated whenever the derived repository diverges from the template.
- [Network integration](./NETWORKING_INTEGRATION.md) — Adapt this guide to connectivity requirements and dependencies, ensuring forks update the section as the topology evolves.

## Operations

- [Operations and standard scripts](./OPERATIONS.md) — Adapt the provided utilities to your project.
- [Automation entrypoints](../scripts/README.md) — Summary of automation entrypoints available in the `scripts/` directory.
- [Compose manifest combinations](./COMPOSE_GUIDE.md) — Organize extra compose files and profiles for different scenarios.
- [Generic backup & restore](./BACKUP_RESTORE.md) — Export/import strategies applicable to any stack.

## Application documentation

- Generate app docs with [`scripts/bootstrap_instance.sh`](../scripts/bootstrap_instance.sh) `--with-docs`, which builds `docs/apps/<application>.md` from [`doc-app.md.tpl`](../scripts/templates/bootstrap/doc-app.md.tpl) and inserts the link under `## Applications`.
- File each application as `docs/apps/<application>.md`, keep the entries under `## Applications` in the right order (e.g., alphabetical), and update them whenever the app is added or changes meaningfully.

## CI/CD automation

- [Workflow overrides](./ci-overrides.md) — Centralizes guidance for adapting or extending pipelines without altering the template’s base workflow.

## Quality and tests

- [Maintaining the test suite](../tests/README.md) — Instructions for configuring, running, and extending the template’s automated tests.
- [`run_quality_checks.sh`](../scripts/run_quality_checks.sh) — Orchestration script that runs the quality validation battery described in the testing documentation.

## Runbooks

- [Primary runbook template](./core.md) — Structure the runbook for your service’s main environment.
- [Auxiliary runbook template](./media.md) — How to document support environments or specialized workloads.

## Applications

- [Application runbooks](./apps/README.md) — Centralize runbooks for each service and ensure forks keep the app index up to date.

## Architectural decisions

- [Decision log](./ADR/0001-multi-environment-structure.md) — Adaptable ADR example for documenting multi-environment scenarios.

## Customization and maintenance

- [Best practices for template heirs](./TEMPLATE_BEST_PRACTICES.md) — Guide derived teams on how to maintain documentation and sync upstream updates.
- [Local notes](./local/README.md) — Centralize runbooks, decisions, and dependencies unique to your stack.
