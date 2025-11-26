# Application runbooks

This folder centralizes documentation specific to each application managed by the stack. Use it to record architecture, sensitive variables, operational flows, and monitoring strategies that do not fit in the generic template documentation.

## How to structure `<app>.md` files

Each application should have a dedicated file named with the app’s short identifier (for example, `docs/apps/minio.md`). The content can follow the suggested format below, equivalent to the template `scripts/templates/bootstrap/doc-app.md.tpl`:

```markdown
# <Application title> (<slug>)

## Overview
- Role in the stack
- External dependencies
- Availability criteria

## Manifests
- Related Compose files (bases and instances)

## Environment variables
- Main affected `env/*.example.env` files

## Operational flows
- Deployment steps, validations, and routine tasks

## Monitoring and alerts
- Metrics, dashboards, and critical notifications

## References
- External documentation, internal guides, and useful links
```

Adapt the sections above as needed to reflect the application’s real behavior and keep instructions updated as the service evolves.

## How to link to the main index

Whenever you create or update a runbook in `docs/apps/`, add the corresponding link in the **Applications** section of [`docs/README.md`](../README.md). This ensures template forks preserve a single, easy-to-navigate index for all documented services.

It is also recommended to reference this directory in other guides (for example, `docs/OPERATIONS.md`) whenever there are procedures that depend on application-specific instructions.
