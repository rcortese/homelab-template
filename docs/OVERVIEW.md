# Overview

> Part of the [documentation index](./README.md). Use it alongside the [Operations](./OPERATIONS.md) and [Network Integration](./NETWORKING_INTEGRATION.md) guides to apply the decisions described here and to wire external dependencies.

## Topology

- **Core (<core-host>)**: control plane of the main service (APIs, schedulers, and critical integrations). External exposure through a dedicated tunnel/proxy (e.g., Cloudflared → `app.domain.com`). Each derived repository must replace `<core-host>` with the corresponding hostname and adjust networking settings in [NETWORKING_INTEGRATION.md](./NETWORKING_INTEGRATION.md).
- **Media (<media-host>)**: heavy workloads and data tasks. No direct public exposure. Focus on local processing. Each derived repository must replace `<media-host>` with the corresponding hostname and review proxy/cross-documentation rules in [NETWORKING_INTEGRATION.md](./NETWORKING_INTEGRATION.md).
  - Use the main application manifest for the media instance (for example, `compose/apps/<your-app>/media.yml` — illustrative path that should be adjusted when renaming the application directory in your fork); the default manifest mounts `${MEDIA_HOST_PATH:-/mnt/data}` as `/srv/media` inside the container. See step 3 of [How to start a derived project](../README.md#how-to-start-a-derived-project) to align the manifests under `compose/` with your stack.
  - Unraid-based projects (or similar platforms) should override `MEDIA_HOST_PATH` in their customized `.env` files (for example, pointing to `/mnt/user`) to reflect the local storage layout.

## Communication between instances

- **Recommended:** MQTT (pub/sub) or internal webhooks.
- **Do not transfer binaries** between instances; pass **paths/metadata** and execute on the media instance via SSH/CLI.

## Standards

- `correlation_id` in every flow and log entry.
- Idempotency: consumers should ignore repeated messages.
- Retention: use `APP_RETENTION_HOURS` to cap history and save storage.
