# Updating from the original template

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
