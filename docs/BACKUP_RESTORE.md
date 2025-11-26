# Generic backup & restore

> Adjust this document to reflect the artifacts and tooling used by your stack. Pair it with the environment runbooks.

## Recommended strategy

1. **Artifact catalog** — list everything that must be preserved (databases, exports, volumes, manifests).
2. **Frequency** — define policies for each artifact (e.g., daily for critical data, weekly for configuration).
3. **Storage** — document where backups live (local, cloud, external storage) and how to access them.
4. **Restore tests** — schedule regular runs to ensure the artifacts work.

## Backup process

- Identify the command/script responsible for extraction (e.g., `scripts/export_*.sh`, `pg_dump`, `restic`).
- Use `scripts/backup.sh <instance>` to pause the stack, copy persisted data to `backups/`, and resume it afterwards.
- Document required parameters (targets, dates, temporary directories).
- Record how to version or tag the resulting artifacts.
- Explain where to archive success/error reports.

### Automated backup script

`scripts/backup.sh` encapsulates the standard **stop ➜ copy data ➜ restart** sequence. Keep in mind:

- Prerequisites: `env/local/<instance>.env` configured, data directories accessible, and free space in `backups/`.
- The final directory follows `backups/<instance>-<YYYYMMDD-HHMMSS>`. Use `date` with the appropriate `TZ` if you need snapshots in different time zones.
- Logs go to stdout/stderr; redirect them when integrating with automations (e.g., `scripts/backup.sh core > logs/backup.log 2>&1`).
- For scenarios with extra data, export it before running the script (e.g., database dumps) and move the artifacts into the generated directory.
- Before stopping the stack, the script lists running services by calling `docker compose ps --status running --services` via `scripts/compose.sh`. The returned names are combined with `deploy_context` to preserve the expected restart order.
- Only services detected as active at the start are restarted. If no service was running before the backup, the script exits without bringing new services up, keeping the stack state intact.

#### Testing the flow

- Lint the script with `shfmt -d scripts/backup.sh` and `shellcheck scripts/backup.sh`.
- Automated tests that validate stop/copy/restart: `pytest tests/backup_script -q`.
- Add restore checks on a defined cadence (e.g., monthly) by copying the snapshot to an isolated environment.

## Restore process

1. Validate artifact integrity (checksums, signatures, schema versions).
2. Restore in a controlled environment using the same manifests/variables as the primary environment.
3. Document manual steps (migrations, reindexing, cache invalidation) and owners.
4. After success, update the corresponding runbook with the date, backup source, and notes.

## Cross-references

- `docs/core.md` and `docs/media.md` (or equivalents) should point to the relevant backups per environment.
- ADRs can record decisions on retention, encryption, or adopted tools.
- Specific scripts should link to this page explaining accepted arguments and prerequisites.

Keep the document updated as new services are added to the derived project.
