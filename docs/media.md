# Runbook template: auxiliary environment

> Use this template for supporting environments (heavy processing, staging, lab, DR). Adjust terminology to reflect your project’s reality.

## Environment context

- **Purpose:** describe why it exists (for example, asynchronous workloads, testing, partner integrations).
- **Constraints:** indicate access policies, resource limits, or isolation requirements.
- **Internal integrations:** list services that depend on this environment or are consumed by it.

## Deploy and post-deploy checklist

Follow the [generic checklist](./OPERATIONS.md#generic-deploy-and-post-deploy-checklist) and, for the auxiliary environment, add:

- **Contextualized preparation:** when updating `env/local/<environment>.env`, record quotas, experimental flags, and limits that differ from the primary environment to maintain traceability for tests and heavy workloads.
- **Additional documentation:** after running `scripts/deploy_instance.sh <environment>`, list migrations, test data loads, or feature flags enabled to make future reproductions easier.
- **Focused post-deploy:** beyond `scripts/check_health.sh <environment>`, validate processing queues, media mounts, and integrations consumed by partner teams, updating the agreed communication channel (for example, Slack, wiki, or test spreadsheet).

## Recovery checklist

1. Sync relevant backups (cold data, snapshots, exports from automated processes).
2. Perform the restore following the instructions in [`docs/BACKUP_RESTORE.md`](./BACKUP_RESTORE.md), adapting to this environment’s requirements.
3. Validate dependent integrations (for example, processing queues, volume mounts, media pipelines).
4. Inform stakeholders about status and differences compared to the primary environment.

## Specific operations

- **Health checks:** detail endpoints, commands, or dashboards used to confirm the environment state.
- **Recurring tasks:** record automated routines (cache cleanup, artifact sync, scheduled upgrades).
- **Experiments:** if the environment supports experimental features, document entry/exit criteria and owners.

## References

- (`compose/docker-compose.common.yml`, when present) + `docker-compose.<environment>.yml`
- [Docker Compose combination guide](./COMPOSE_GUIDE.md#stacks-with-multiple-applications) to plan enablement/disablement of auxiliary applications.
- `env/<environment>.example.env`
- Additional required scripts (for example, data seeds, converters)
- ADRs that justify this environment’s existence
