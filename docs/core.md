# Runbook template: primary environment

> Adapt this document to represent your service’s main environment (production, control, etc.). Use it as a shared operational checklist across teams.

## Environment context

- **Function:** describe the environment’s role (for example, control plane, production, critical workload).
- **External dependencies:** list required services, databases, or integrations.
- **Criticality:** detail availability objectives, RTO/RPO, and escalation contacts.

## Deploy and post-deploy checklist

Follow the [generic checklist](./OPERATIONS.md#generic-deploy-and-post-deploy-checklist) and, for the primary environment, add:

- **Hardened preparation:** generate `scripts/describe_instance.sh <environment> --format json` and archive the report in the audit system before starting the change.
- **Execution evidence:** when running `scripts/deploy_instance.sh <environment>`, capture image hashes, pipeline IDs, and formal approvals, attaching them to the change-management record.
- **Critical post-deploy:** after `scripts/check_health.sh <environment>`, validate availability dashboards and confirm with the SRE owner that priority alerts remained stable.

> Replace `<environment>` with the real identifier used in the project.

## Recovery checklist

1. Ensure access to backup artifacts documented in [`docs/BACKUP_RESTORE.md`](./BACKUP_RESTORE.md).
2. Restore services using the official commands (document them step by step here).
3. Validate critical endpoints, queues, or routines.
4. Update incident tickets with timelines, owners, and final status.

## Recurring operations

- **Health checks:** describe commands/dashboards used daily.
- **Cleanup routines:** define scheduled tasks (log cleanup, backup rotation, etc.).
- **Audits:** list periodic reviews (security, compliance, planned upgrades).

## References

- (`compose/base.yml`, when present) + `docker-compose.<environment>.yml`
- [Docker Compose combination guide](./COMPOSE_GUIDE.md#stacks-with-multiple-applications) to guide application enablement/disablement.
- `env/<environment>.example.env`
- ADRs related to the creation/maintenance of this environment
- Custom scripts and key dashboards
