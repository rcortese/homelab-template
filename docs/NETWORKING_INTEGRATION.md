# Integration with external infrastructure

> Use this document to describe how the derived stack interacts with components outside the repository (network, authentication, observability, etc.).

## How to document dependencies

1. **External components** — list third-party services (reverse proxies, DNS, tunnels, message queues, storage) responsible for exposing or supporting the stack.
2. **Owners** — identify the teams or repositories that maintain each component.
3. **Contracts** — describe endpoints, ports, domains, API keys, and authentication requirements.
4. **Sync checklists** — detail mandatory steps whenever a change affects the external components.

## Example table

| Component | Owner | Responsibilities | Inputs/Outputs |
| --- | --- | --- | --- |
| Reverse proxy | Platform team | TLS termination, hostname routing, security headers. | Receives public traffic → forwards to `compose/base.yml` (when present) + [`compose/<instance>.yml`](../compose/core.yml) *(when present)* + `compose/apps/<app>/<instance>.yml`. |
| Internal DNS | Network team | Publishes records for internal/external environments. | Update `A`/`CNAME` records after host changes. |
| Observability | SRE | Collects metrics and logs, generates alerts. | Dashboards and alerts that monitor runbook-documented health checks. |

Replace the table above with the real components in your infrastructure.

## Recommended change flow

1. Open tickets or PRs in the repositories responsible for the affected components.
2. Update environment variables and manifests in this repository to reflect new values (domains, ports, credentials).
3. Run validation scripts and follow runbooks to apply the change.
4. Document results (deployment logs, external validations) and reference them here.

## Incidents and troubleshooting

- Record how to reach the teams responsible for each external component.
- Document useful commands (e.g., `dig`, `curl`, `traceroute`, observability tools).
- Keep a history of relevant incidents with links to post-mortems or ADRs that adjusted the integration.

## Related documents

- Environment runbooks (`docs/core.md`, `docs/media.md`, or equivalents)
- Variables guide (`env/README.md`)
- ADRs that formalize critical integrations
