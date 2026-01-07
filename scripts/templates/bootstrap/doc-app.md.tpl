# {{APP_TITLE}} ({{APP}})

> Replace the blocks below with real application details as soon as the bootstrap is complete. See `docs/apps/README.md` for general guidance on keeping application runbooks organized.

## Overview

- Role in the stack:
- External dependencies:
- Availability criteria:

## Manifests

- `compose/apps/{{APP}}/base.yml`
- `compose/apps/{{APP}}/{{INSTANCE}}.yml`
- `compose/docker-compose.base.yml`

## Environment variables

- `env/common.example.env`
- `env/{{INSTANCE}}.example.env`

## Operational flows

1. Update `compose/apps/{{APP}}/{{INSTANCE}}.yml` with real ports, volumes, and secrets.
2. Fill in `env/{{INSTANCE}}.example.env` with environment-specific guidance.
3. Run `scripts/validate_compose.sh` to ensure the new combination is valid.
4. Record additional checks in `docs/OPERATIONS.md` as needed.

## Monitoring and alerts

- Monitored services:
- Dashboards and panels:
- Critical alerts:

## References

- Useful links:
- Additional documentation:
