# Template tests

This directory contains the tests that ship with the template and must remain intact to simplify future updates. To add project-specific tests in derived repositories, create them outside this directory and orchestrate execution through the overridden workflow `.github/workflows/project-tests.yml`. See `docs/ci-overrides.md` for the full walkthrough.

## Test organization

Test cases that exercise commands in `scripts/` are centralized in `tests/scripts/`. Each subdirectory is named after the corresponding command (for example, `tests/scripts/check_all/` covers the `scripts/check_all.sh` wrapper) and should contain an `__init__.py` to allow relative imports between test modules. When adding checks for a new command, create a directory with the same name in `tests/scripts/`, move/add the `test_*.py` files inside it, and consume shared utilities via `tests/helpers/`.

## How to run

To quickly validate the template suite locally, use `pytest -q` in the repository root. As a broader alternative, run the `scripts/run_quality_checks.sh` script, which reproduces the sequence of quality checks invoked by the `project-tests.yml` workflow in GitHub Actions.
