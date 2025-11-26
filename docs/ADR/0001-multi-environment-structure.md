# ADR 0001 — Multi-environment structure for derived services

## Status

Accepted

## Context

When reusing this template, it is common to split responsibilities across multiple environments (for example, production vs. heavy processing, control vs. lab). We need an initial convention that serves as a reference to document these splits and guide scripts/runbooks.

## Decision

- Keep at least two named environments (`<primary-environment>` and `<auxiliary-environment>`) when starting a derived project.
- Record separate runbooks in `docs/core.md` and `docs/media.md` (or equivalent renamings) covering deploy, recovery, and recurring operations checklists.
- Define environment-specific variables and manifests for each environment, keeping the templates in `env/` and `compose/`.
- Document shared external dependencies in [`docs/NETWORKING_INTEGRATION.md`](../NETWORKING_INTEGRATION.md) to ensure impacts are mapped by environment.

## Consequences

- Derived projects have a clear starting point to split workloads, which facilitates scalability and isolation.
- Template scripts and validations can be reused without deep changes, requiring only the desired environment name.
- If a project needs only one environment, the team must record a new ADR explaining the change and update the corresponding documentation.
