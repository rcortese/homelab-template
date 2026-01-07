# Homelab service template

This repository is a **reusable template** for self-contained stacks. It bundles infrastructure as code, operation scripts, and documentation under a single convention to make forks or derivative projects easier to maintain.

If you just forked or templated the project, follow the [onboarding guide](docs/ONBOARDING.md) to handle prerequisites, bootstrap the repository, and run the initial validation (`scripts/check_all.sh`) before customizing anything in [Local documentation and customization](#local-documentation-and-customization).

We keep this file generic to simplify syncing with new template versions. Stack-specific information should live in the local notes indicated in [Local documentation and customization](#local-documentation-and-customization).

## Prerequisites and validation snapshot

- Docker Engine **>= 24.x** with Compose v2.20+ (only hard requirements for running the stack)
- Optional contributor tooling: Python **>= 3.11** plus `shellcheck` **>= 0.9.0**, `shfmt` **>= 3.6.0**, and `checkbashisms` for local lint/format
- Validate setup: `scripts/check_all.sh` (structure/env/compose checks using Docker and Compose)

Operational procedures and runbooks live in [`docs/OPERATIONS.md`](docs/OPERATIONS.md). For template update instructions, see [`docs/updating-from-template.md`](docs/updating-from-template.md).

## Required contents

Every derived repository must keep the minimum set of directories described in the template. For the complete list—the single source of truth—see the [table of required directories in `docs/STRUCTURE.md`](docs/STRUCTURE.md#required-directories). It details purposes, content examples, and serves as the central reference for structural updates.

CI/CD pipelines, tests, and additional scripts can be added, but the directories listed in the table must remain to preserve compatibility with the template utilities.

## How to start a derived project

1. Click **Use this template** (or fork it) to create a new repository.
2. Update the project name and metadata in the newly created `README.md` with your stack’s context.
3. Review [`compose/`](docs/COMPOSE_GUIDE.md) and [`env/`](env/README.md) files to align services, ports, and variables with your needs.
4. Adjust documentation in `docs/` following the guidance in the [Local documentation and customization](#local-documentation-and-customization) section of this template.
5. Run the validation flow (`scripts/check_all.sh`) before the first commit.

## Suggested flow for new repositories

1. **Modeling** – record goals, requirements, and initial decisions in ADRs (`docs/ADR/`).
2. **Infrastructure** – create manifests in `compose/` and map the corresponding variables in `env/`.
3. **Automation** – adapt existing scripts to the new stack and document usage in `docs/OPERATIONS.md`.
4. **Runbooks** – customize operational guides (`docs/core.md`, `docs/media.md`, etc.) to reflect real environments.
5. **Quality** – keep `.github/workflows/` with `template-quality.yml` intact and add extra workflows as needed, documenting safe adjustments in [`docs/ci-overrides.md`](docs/ci-overrides.md). See also [`tests/README.md`](tests/README.md) to learn about the template’s default test suite.

<a id="local-documentation-and-customization"></a>
## Local documentation and customization

Navigate via the [index in `docs/README.md`](docs/README.md), which organizes the stack lifecycle and indicates when to dive deeper into each topic. When you need to record runbooks, decisions, or stack-specific dependencies, use [`docs/local/`](docs/local/README.md) as the entry point for materials unique to your stack.

By concentrating customizations in these materials you get:
- fewer conflicts during rebases or merges from the template;
- a dedicated place to find repository-specific details;
- fewer edits to this `README.md`, keeping it aligned with the template’s general guidance.

The rest of the template then remains a reference and only needs occasional tweaks when necessary.
