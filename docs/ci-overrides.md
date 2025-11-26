# Guidelines for overriding CI tests in derived projects

To keep updates simple when this template ships new versions, concentrate CI customizations in the files below.

## Recommended flow

1. **Do not modify** `.github/workflows/template-quality.yml` in derived projects. This workflow covers the basic checks provided by the template (shell lint, infrastructure validations, and the main test suite).
2. Create or update `.github/workflows/project-tests.yml` in the derived project to add specific jobs (for example, application code lint, extra smoke tests, or project-specific infrastructure validations).
3. Use the `workflow_call` trigger in `project-tests.yml` to define the required jobs. The parent workflow already references this file through `uses: ./.github/workflows/project-tests.yml`.
4. When new template versions are integrated, customizations remain isolated in the overridden file, reducing merge conflicts.

## Where to create new tests

- **Shared Python tests:** keep adding them to the `tests/` directory in the template, as long as they make sense for every derived project.
- **Derived-project-specific tests:** keep them outside the template and focus orchestration in the overridden `.github/workflows/project-tests.yml`.

> Tip: when overriding the workflow, preserve the main job name (for example, `project-tests`) to keep the history view consistent with the template.
