# Local stack notes

> This directory is reserved for documenting adaptations specific to derived repositories.
>
> Editing these files should not cause significant conflicts when syncing with the template, as long as template maintainers avoid modifying them after the initial creation.

Use this space to centralize information that falls outside the template’s generic scope:

- Stack descriptions, business context, and service objectives.
- Dedicated runbooks (incident response, alternative deployments, exclusive integrations).
- Optional dependencies or additional tools present only in the derived repository.
- Quick record of applied customizations (with links to ADRs, issues, or relevant PRs).

## Organization suggestions

1. Create subfolders to separate environments (`production/`, `staging/`) or functional domains.
2. Use a local `CHANGELOG.md` to list syncs with the template and relevant adjustments.
3. Point to these documents from the project-specific `README.md` to avoid duplicating content.

## Merge conventions

- The template’s `.gitattributes` configures `merge=ours` to keep your changes in `docs/local/` during updates.
- Even so, review diffs after running `scripts/update_from_template.sh` to ensure no essential note was lost.

Feel free to reorganize this directory as needed—just keep a clear index in this `README.md` or an equivalent file you choose.
