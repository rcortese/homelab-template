# Template tests

This directory contains the tests that ship with the template and must remain intact to simplify future updates. To add repository-specific tests, create them outside this directory and orchestrate execution through the overridden workflow `.github/workflows/project-tests.yml`. See `docs/ci-overrides.md` for the full walkthrough.

## Test organization

Cases that exercise the commands in `scripts/` are centralized under `tests/scripts/`. Each subdirectory uses the corresponding command name (for example, `tests/scripts/check_all/` covers the `scripts/check_all.sh` wrapper) and must include an `__init__.py` to allow relative imports between test modules. When adding checks for a new command, create a namesake directory under `tests/scripts/`, move/add the `test_*.py` files inside it, and consume shared utilities via `tests/helpers/`.

## How to run

To quickly validate the template suite locally, run `pytest -q` from the repository root. As a broader alternative, execute `scripts/run_quality_checks.sh`, which reproduces the sequence of checks invoked by the `project-tests.yml` workflow on GitHub Actions.
