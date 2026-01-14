# Template onboarding guide

This playbook summarizes the recommended first steps for anyone deriving the template. It consolidates prerequisites, the `env/local` bootstrap, and the mandatory validations before the first commits. This document is the official checklist for the template’s initial validations.

## 1. Install the base dependencies

This is the canonical reference for dependencies required by the template. Ensure the development machine has the tools below installed (even when using remote environments such as Codespaces or temporary VMs):

- Docker Engine **>= 24.x** (or an equivalent stable version that supports integrated Compose v2)
- Docker Compose **v2.20+** (for compatibility with current profiles and validations)
- Python **>= 3.11** (necessary to run automation scripts and test suites)
- Shell lint/format tools: `shellcheck` **>= 0.9.0**, `shfmt` **>= 3.6.0**, and `checkbashisms` (or equivalent tools configured in local pipelines)

> Whenever the template requires new tools or minimum versions, this list is updated first.

## 2. Prepare the `env/local` files

1. Create the Git-ignored directory:
   ```bash
   mkdir -p env/local
   ```
2. Run the bootstrap to create manifests, `env/*.example.env` templates, and optional documentation for a new instance:
   ```bash
   scripts/bootstrap_instance.sh <application> <instance>
   # add --with-docs to generate the stubs in docs/apps/
   ```
3. Fill in the generated files at `env/<instance>.example.env` and copy them to `env/local/` as described in the [variable guide](../env/README.md#how-to-generate-local-files).

> When reusing existing instances from the template, manually copy the `env/*.example.env` templates to `env/local/` and update the sensitive values following the same guide.

## 3. Set up the Python environment

Prefer a local Python interpreter when running the helper scripts. If `requirements-dev.txt` is present, install the local depend
encies first:

```bash
pip install -r requirements-dev.txt
```

Only fall back to Docker-based wrappers when a local interpreter is unavailable or when the repository is explicitly configured
to enforce containerized execution (for example, to isolate dependencies from host toolchains).

## 4. Run the consolidated validations

With the `env/local` files ready and dependencies installed, execute:

```bash
scripts/check_all.sh
```

The `scripts/check_all.sh` aggregator runs the template’s essential structural validations in the order below and stops immediately when any of them fails:

- `scripts/check_structure.sh` – confirms required directories and files are still present.
- `scripts/check_env_sync.sh` – verifies that Compose manifests and `env/*.example.env` files remain in sync (tries local Python via `scripts/_internal/lib/python_runtime.sh`, then falls back to Docker for `scripts/_internal/python/check_env_sync.py`).
  - Use `--instance <name>` (repeatable) when you want to validate only a subset of instances during local adjustments.
- `scripts/validate_env_output.sh` – confirms generated environment output matches the expected templates before Compose validation.
- `scripts/validate_compose.sh` – validates the default manifest combinations for the active profiles.

Use `scripts/run_quality_checks.sh` when you want to quickly run the base quality battery without going through every validation — the helper chains `pytest`, `shfmt`, `shellcheck`, and `checkbashisms`. Add `--no-lint` if you only want to run `pytest`.

## 5. Next steps

- Review the [full documentation index](./README.md) to find specific runbooks and guides.
- Use [`docs/TEMPLATE_BEST_PRACTICES.md`](./TEMPLATE_BEST_PRACTICES.md) as a reference when adapting the template.
- Centralize fork-specific information in [`docs/local/`](./local/README.md).

Following this playbook ensures the derived repository starts with the minimum conventions aligned with the official template.
