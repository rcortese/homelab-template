# Best practices for template inheritors

This guide helps teams creating derived repositories stay consistent with the original template and simplify future updates.

## Organizing local documentation

- **Centralize the index**: update `docs/README.md` with links to project-specific guides while keeping it generic.
- **Up-to-date runbooks**: keep `docs/core.md` and `docs/media.md` (or equivalents) aligned with real operations.
- **Decision history**: record architectural choices in `docs/ADR/` using the `YYYY-sequence-title.md` convention.
- **Explicit customizations**: use `docs/local/` to document deviations from the template (for example, extra directories or replaced scripts) and reference them from this page.

## Tracking customizations

1. List relevant adaptations right after creating the derived repository (for example, extra variables, removed scripts, or project-specific pipelines) in the `docs/local/` index.
2. Include cross-references to PRs, issues, and ADRs that justify each customization.
3. Update the derived project’s `README.md` with enough context for new contributors.

## Staying aligned with the template

- **Periodic synchronization**: schedule quarterly or semiannual reviews to compare the derived repository against the template.
- **Upstream update script**: use `scripts/update_from_template.sh` to reapply local commits on top of the template branch. Run it first with `--dry-run`, confirm the remotes/commits used, and only then apply the full update.
- **Update checklist**:
  1. Fetch changes from the template (pull/fetch).
  2. Run the merge script or apply patches manually.
  3. Resolve conflicts while keeping documented local customizations and prioritizing the contents of `docs/local/`.
  4. Run validations (`scripts/check_structure.sh`, tests, linters).
  5. Update this page or `docs/local/CHANGELOG.md` with the sync date and notes.

## Communication and governance

- Define owners for the derived repository and reviewers for upstream updates.
- Document communication channels (Slack, email, issues) to handle questions or incidents.
- Encourage PRs that improve the template based on lessons learned in child projects.

Keep this document visible to new teams to promote a culture of living documentation and ongoing alignment.
