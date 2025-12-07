# AGENTS.md — Thin Contract for Coding Agents (Codex-only)
>
> This file instructs **LLM agents**, not humans. Long explanations, tutorials, and rationale live in `docs/`. The repository is a reusable template for self-contained stacks (IaC + ops scripts + docs) with required folders: `compose/`, `env/`, `docs/`, `scripts/`.
>
## 1) Repository Structure & Profiles (Invariant)

- Keep directory layout and file names stable. Do **not** rename or move `compose/`, `env/`, `docs/`, `scripts/`.
- Two generic profiles: **core** (Ubuntu) and **media** (Unraid). Compose definitions must remain profile-safe.
- Required ops scripts exist in `scripts/`: `check_structure.sh`, `validate_compose.sh`, `deploy_instance.sh`, `build_compose_file.sh`, `check_health.sh`, etc.

## 2) Global Invariants (Must Always Hold)

- Docker **Compose v2** only; `docker compose config -q` must pass for all profiles.
- All shell scripts must pass **ShellCheck** (no blanket disables) and **shfmt** (formatted); run **checkbashisms** for `/bin/sh` scripts.
- Every `${VAR}` referenced by Compose must exist in the matching `env/*.example.env`; no orphan or unused vars remain in examples.
- No secrets in repo; never write real values to `*.example.env`.
- Commits are **atomic**, minimally scoped, and descriptive. Do not modify CI workflows or directory structure unless instructed.

## 3) Idempotent Validation Loop (run after any edit)

```pseudo
MAX_ITERS = 3
for i in 1..MAX_ITERS:
  lint_shell()                 # shellcheck, shfmt, checkbashisms
  sync_env_compose()           # keep compose <-> env/*.example.env in sync
  sanity_yaml()                # parse YAML; check references (services, nets, vols)
  validate_compose_profiles(['core','media'])  # docker compose config -q
  run_smoke_tests()            # pytest or minimal health checks
  if all_green: commit_and_exit()
  if i == MAX_ITERS: open_issue_and_exit()     # request human review
  auto_fix(); continue
```

## 4) Local Agent Heuristics (Python-only; no Docker required)

- Parse Compose YAML(s); collect `${VAR}` with regex; compare to `env/*.example.env`. Add missing placeholders; flag obsolete ones (do not delete automatically).
- YAML sanity: `safe_load` all compose files; fail early on syntax; verify `depends_on` names, volumes, networks, and profiles exist.
- Shell: if available, run `shfmt -w` and `shellcheck`; else rely on CI but still attempt obvious fixes (quoting, `[ ... ]` vs `[[ ... ]]`, set `-euo pipefail` where appropriate).
- Never alter service names, profile keys, or required healthcheck contracts.

## 5) CI Contract (GitHub Actions)

- Triggers: `push` and `pull_request`. Concurrency cancels in-progress runs per branch.
- Jobs (minimal): **lint_shell** (shellcheck + shfmt + checkbashisms), **compose_check** (`docker compose config -q` for profiles), **tests** (`pytest -q` smoke).
- Artifacts: on failure, upload relevant logs (e.g., `docker compose logs <svc>`). Agent should anticipate and pass these checks locally.

## 6) Failure → Agent Action

- Shell lint fails → Fix per diagnostics; rerun loop.
- `compose config` fails → Fix YAML or missing env var; rerun loop.
- Tests/health fail → Inspect logs; adjust config or code; rerun loop.
- Regressions after a fix → Reapply loop until stable or `MAX_ITERS`.
- `MAX_ITERS` reached → Stop changing; open issue/PR with remaining errors.

## 7) Platform Notes (succinct)

- **Ubuntu (core):** Compose v2 available; install `shellcheck`, `shfmt` if running locally.
- **Unraid (media):** Compose v2 available; do not change container networks/IPs; volumes under `/mnt/user/...`; respect `PUID/PGID`. If tooling is absent locally, rely on CI; still validate Compose syntax.
- **Tooling availability:** If you have internet access within the execution environment, install both `shellcheck` and `shfmt` before running shell linting commands to ensure they are available.

## 8) Do’s / Don’ts

**Do:** preserve layout; keep examples in sync; make one-purpose commits; format/lint before commit; reference docs for human-facing details.  
**Don’t:** suppress linters to “green” the CI; leak secrets; change CI/pipelines; rewrite directory structure; introduce breaking network/IP changes on Unraid.

## 9) Pointers (for the agent)

- Human-facing runbooks, ADRs, and extended guides live under `docs/`. Use them for context; do not inline here.
- Required checks may also be invoked via `scripts/check_structure.sh` and `scripts/validate_compose.sh` in forks.
