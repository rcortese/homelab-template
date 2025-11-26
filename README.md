# Homelab service template

This repository serves as a **reusable template** for self-contained stacks. It brings together infrastructure as code, operations scripts, and documentation under a single convention to simplify forks or derivative projects.

If you just forked the template, start with the [onboarding guide](docs/ONBOARDING.md) to follow the recommended initial flow. Next, use the [Local documentation and customization](#documentacao-e-customizacao-local) section of this file to orient yourself when organizing materials.

We keep this file generic to make syncing with new template versions easier. Specific information about your stack should be described in the local notes indicated in [Local documentation and customization](#documentacao-e-customizacao-local).

## Prerequisites

Before you begin, check the dependencies section in the [onboarding guide](docs/ONBOARDING.md). There we maintain the complete, always up-to-date list of required tools (including minimum versions and compatible alternatives) to prepare the environment.

### Quick checklist

Follow the [onboarding guide](docs/ONBOARDING.md) step by step to prepare the environment and validations.

> When you create an onboarding guide specific to your stack, replicate this sequence to keep instructions aligned between documents.

## Required content

Every derived repository must keep the minimum set of directories described in the template. For the full list—the single source of truth—see the [table of required directories in `docs/STRUCTURE.md`](docs/STRUCTURE.md#diretórios-obrigatórios). It details purposes, content examples, and serves as the central reference for structural updates.

CI/CD pipelines, tests, and additional scripts can be added, but the directories listed in the table must be preserved to maintain compatibility with the template utilities.

## How to start a derived project

1. Click **Use this template** (or create a fork) to generate a new repository.
2. Update the project name and metadata in the newly created `README.md` with your stack’s context.
3. Review the [`compose/`](docs/COMPOSE_GUIDE.md) and [`env/`](env/README.md) files to align services, ports, and variables with your needs.
4. Adjust the documentation in `docs/` following the guidelines in the [Local documentation and customization](#documentacao-e-customizacao-local) section of this template.
5. Run the validation flow (`scripts/check_all.sh`) before the first commit.

After the bootstrap, you can already validate the stack locally to ensure the initial services start as expected.

```bash
scripts/bootstrap_instance.sh app core
scripts/compose.sh core up -d
scripts/check_health.sh core
```

Remember to adjust the `<app>`/`core` values to reflect your fork’s profiles and refer to [`docs/OPERATIONS.md`](docs/OPERATIONS.md) for detailed instructions.

## Suggested flow for new repositories

1. **Modeling** – record objectives, requirements, and early decisions in the ADRs (`docs/ADR/`).
2. **Infrastructure** – create the manifests in `compose/` and model the corresponding variables in `env/`.
3. **Automation** – adapt the existing scripts to the new stack and document usage in `docs/OPERATIONS.md`.
4. **Runbooks** – customize the operational guides (`docs/core.md`, `docs/media.md`, etc.) to reflect real environments.
5. **Quality** – keep `.github/workflows/` with `template-quality.yml` intact and add extra workflows as needed, documenting safe adjustments in [`docs/ci-overrides.md`](docs/ci-overrides.md). Also check [`tests/README.md`](tests/README.md) to learn about the template’s default test suite.

<a id="documentacao-e-customizacao-local"></a>
## Local documentation and customization

Centralize your navigation using the [index in `docs/README.md`](docs/README.md), which organizes the stack life cycle and indicates when to dig into each topic. When you need to record runbooks, decisions, or specific dependencies, use the [`docs/local/`](docs/local/README.md) directory as the entry point for materials specific to your stack.

By concentrating customizations in these materials you get:
- fewer conflicts during rebases or merges from the template;
- a dedicated place to find repository-specific details;
- fewer edits to this `README.md`, which stays aligned with the template’s general instructions.

This way, the rest of the template continues to serve as a reference and only requires occasional adjustments when needed.

## Updating from the original template

This section is the canonical reference for the template update flow. Any summary in other documents points back to these instructions.

Derived repositories can reapply their customizations on top of the latest template version using `scripts/update_from_template.sh`. The suggested flow is:

1. Configure the remote that points to the template, for example `git remote add template git@github.com:org/template.git`.
2. Identify the template commit used as the initial base (`ORIGINAL_COMMIT_ID`) and the first exclusive local commit (`FIRST_COMMIT_ID`). Use `scripts/detect_template_commits.sh` to automatically calculate these values and store the result in `env/local/template_commits.env` (the script creates the directory if it does not exist).
3. Run a dry run by providing parameters through flags:

   ```bash
   scripts/update_from_template.sh \
     --remote template \
     --original-commit <initial-template-hash> \
     --first-local-commit <first-local-commit-hash> \
     --target-branch main \
     --dry-run
   ```

4. Remove `--dry-run` to apply the rebase and resolve any conflicts before opening a PR.
5. Finish by running the stack tests (for example, `python -m pytest` and `scripts/check_structure.sh`; adjust as described in [`docs/OPERATIONS.md`](docs/OPERATIONS.md)).

The script displays clear messages about the commands executed (`git fetch` followed by `git rebase --onto`) and fails early if the provided commits do not belong to the current branch.
