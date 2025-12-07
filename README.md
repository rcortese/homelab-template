# Homelab service template

This repository is a **reusable template** for self-contained stacks. It bundles infrastructure as code, operation scripts, and documentation under a single convention to make forks or derivative projects easier to maintain.

If you just forked or templated the project, start with the [onboarding guide](docs/ONBOARDING.md) to follow the recommended initial flow. Then use the [Local documentation and customization](#local-documentation-and-customization) section of this file to organize your materials.

We keep this file generic to simplify syncing with new template versions. Stack-specific information should live in the local notes indicated in [Local documentation and customization](#local-documentation-and-customization).

## Prerequisites

Before getting started, review the dependencies section in the [onboarding guide](docs/ONBOARDING.md). It contains the complete, always up-to-date list of tools (including minimum versions and compatible alternatives) needed to prepare the environment.

### Quick checklist

Follow the step-by-step instructions in the [onboarding guide](docs/ONBOARDING.md) to prepare the environment and validations.

> When you create a stack-specific onboarding guide, mirror this sequence to keep the instructions aligned across documents.

## Required contents

Every derived repository must keep the minimum set of directories described in the template. For the complete list—the single source of truth—see the [table of required directories in `docs/STRUCTURE.md`](docs/STRUCTURE.md#required-directories). It details purposes, content examples, and serves as the central reference for structural updates.

CI/CD pipelines, tests, and additional scripts can be added, but the directories listed in the table must remain to preserve compatibility with the template utilities.

## How to start a derived project

1. Click **Use this template** (or fork it) to create a new repository.
2. Update the project name and metadata in the newly created `README.md` with your stack’s context.
3. Review [`compose/`](docs/COMPOSE_GUIDE.md) and [`env/`](env/README.md) files to align services, ports, and variables with your needs.
4. Adjust documentation in `docs/` following the guidance in the [Local documentation and customization](#local-documentation-and-customization) section of this template.
5. Run the validation flow (`scripts/check_all.sh`) before the first commit.

After bootstrapping, you can validate the stack locally to ensure the initial services start as expected.

```bash
scripts/bootstrap_instance.sh app core
scripts/build_compose_file.sh --instance core
docker compose -f docker-compose.yml up -d
scripts/check_health.sh core
```

Remember to adjust `<app>`/`core` to match your fork’s profiles, and refer to [`docs/OPERATIONS.md`](docs/OPERATIONS.md) for detailed instructions.

## Suggested flow for new repositories

1. **Modeling** – record goals, requirements, and initial decisions in ADRs (`docs/ADR/`).
2. **Infrastructure** – create manifests in `compose/` and map the corresponding variables in `env/`.
3. **Automation** – adapt existing scripts to the new stack and document usage in `docs/OPERATIONS.md`.
4. **Runbooks** – customize operational guides (`docs/core.md`, `docs/media.md`, etc.) to reflect real environments.
5. **Quality** – keep `.github/workflows/` with `template-quality.yml` intact and add extra workflows as needed, documenting safe adjustments in [`docs/ci-overrides.md`](docs/ci-overrides.md). See also [`tests/README.md`](tests/README.md) to learn about the template’s default test suite.

<a id="local-documentation-and-customization"></a>
## Local documentation and customization

Navigate via the [index in `docs/README.md`](docs/README.md), which organizes the stack lifecycle and indicates when to dive deeper into each topic. When you need to record runbooks, decisions, or stack-specific dependencies, use [`docs/local/`](docs/local/README.md) as the entry point for materials unique to your stack.

By concentrating customizations in these materials you get:
- fewer conflicts during rebases or merges from the template;
- a dedicated place to find repository-specific details;
- fewer edits to this `README.md`, keeping it aligned with the template’s general guidance.

The rest of the template then remains a reference and only needs occasional tweaks when necessary.

## Updating from the original template

This section is the canonical reference for the template update flow. Any summary in other documents points back to these instructions.

Derived repositories can reapply their customizations on top of the latest template version using `scripts/update_from_template.sh`. The suggested flow is:

1. Configure the remote pointing to the template, for example `git remote add template git@github.com:org/template.git`.
2. Identify the template commit used as the initial base (`ORIGINAL_COMMIT_ID`) and the first unique local commit (`FIRST_COMMIT_ID`). Use `scripts/detect_template_commits.sh` to calculate these values automatically and persist the result in `env/local/template_commits.env` (the script creates the directory if it does not exist).
3. Run a simulation by passing the parameters as flags:

   ```bash
   scripts/update_from_template.sh \
     --remote template \
     --original-commit <initial-template-hash> \
     --first-local-commit <first-unique-local-hash> \
     --target-branch main \
     --dry-run
   ```

4. Remove `--dry-run` to apply the rebase and resolve any conflicts before opening a PR.
5. Finish by running the stack tests (for example, `python -m pytest` and `scripts/check_structure.sh`; adjust as described in [`docs/OPERATIONS.md`](docs/OPERATIONS.md)).

The script prints clear messages about the commands executed (`git fetch` followed by `git rebase --onto`) and fails early if the provided commits do not belong to the current branch.
