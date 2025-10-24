# Repository-wide agent instructions

- When modifying any `*.sh` file, you **must** run `shellcheck` on every modified shell script and keep fixing the issues until `shellcheck` exits successfully with no diagnostics for those files.
- Do not address `shellcheck` feedback by suppressing warnings/errors, duplicating code, or changing the directory structure.
- These requirements apply in addition to any other testing or review steps you would normally perform.
