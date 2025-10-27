from __future__ import annotations

import os
import subprocess
from pathlib import Path

import pytest


def _run_bootstrap(repo_root: Path, *args: str, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    script = repo_root / "scripts" / "bootstrap_instance.sh"
    command = ["bash", str(script), *args]
    return subprocess.run(
        command,
        cwd=cwd or repo_root,
        capture_output=True,
        text=True,
        check=False,
        env=os.environ.copy(),
    )


@pytest.mark.parametrize("repo_copy", [("docs",)], indirect=True)
def test_creates_files_and_updates_docs(repo_copy: Path) -> None:
    result = _run_bootstrap(repo_copy, "analytics", "staging", "--with-docs")

    assert result.returncode == 0, result.stderr
    stdout = result.stdout
    assert "[*] Bootstrap concluído com sucesso." in stdout

    base_file = repo_copy / "compose" / "apps" / "analytics" / "base.yml"
    instance_file = repo_copy / "compose" / "apps" / "analytics" / "staging.yml"
    env_file = repo_copy / "env" / "staging.example.env"
    doc_file = repo_copy / "docs" / "apps" / "analytics.md"
    docs_readme = repo_copy / "docs" / "README.md"

    assert base_file.is_file()
    assert instance_file.is_file()
    assert env_file.is_file()
    assert doc_file.is_file()

    base_content = base_file.read_text(encoding="utf-8")
    instance_content = instance_file.read_text(encoding="utf-8")
    env_content = env_file.read_text(encoding="utf-8")
    doc_content = doc_file.read_text(encoding="utf-8")

    assert "services:" in base_content
    assert "analytics:" in base_content

    assert "container_name" not in instance_content
    assert "${ANALYTICS_STAGING_PORT:-8080}" in instance_content
    assert "APP_PUBLIC_URL" in instance_content

    assert "ANALYTICS_STAGING_PORT=8080" in env_content
    assert "SERVICE_NAME" not in env_content

    assert "# Analytics (analytics)" in doc_content
    assert "compose/apps/analytics/base.yml" in doc_content
    assert "env/staging.example.env" in doc_content

    docs_index = docs_readme.read_text(encoding="utf-8")
    assert "## Aplicações" in docs_index
    assert "[Analytics](./apps/analytics.md)" in docs_index


def test_fails_when_targets_exist(repo_copy: Path) -> None:
    app_dir = repo_copy / "compose" / "apps" / "existing"
    app_dir.mkdir(parents=True)
    base_file = app_dir / "base.yml"
    base_file.write_text("services: {}\n", encoding="utf-8")

    result = _run_bootstrap(repo_copy, "existing", "demo")

    assert result.returncode == 1
    stderr = result.stderr
    assert "já existem" in stderr
    assert str(base_file) in stderr

    instance_file = app_dir / "demo.yml"
    env_file = repo_copy / "env" / "demo.example.env"

    assert not instance_file.exists()
    assert not env_file.exists()


def test_accepts_custom_base_dir(repo_copy: Path) -> None:
    scripts_dir = repo_copy / "scripts"
    result = _run_bootstrap(repo_copy, "demo", "qa", "--base-dir", str(repo_copy), cwd=scripts_dir)

    assert result.returncode == 0, result.stderr

    instance_file = repo_copy / "compose" / "apps" / "demo" / "qa.yml"
    env_file = repo_copy / "env" / "qa.example.env"

    assert instance_file.is_file()
    assert env_file.is_file()


def test_override_only_mode_skips_base(repo_copy: Path) -> None:
    app_dir = repo_copy / "compose" / "apps" / "overrides"
    app_dir.mkdir(parents=True)
    existing_override = app_dir / "core.yml"
    existing_override.write_text("services: {}\n", encoding="utf-8")

    instance_name = "sandbox"
    result = _run_bootstrap(repo_copy, "overrides", instance_name, "--override-only")

    assert result.returncode == 0, result.stderr
    stdout = result.stdout

    base_file = app_dir / "base.yml"
    instance_file = app_dir / f"{instance_name}.yml"
    env_file = repo_copy / "env" / f"{instance_name}.example.env"

    assert not base_file.exists(), "base.yml should not be created in override-only mode"
    assert instance_file.is_file()
    assert env_file.is_file()

    listed_lines = [line.strip() for line in stdout.splitlines() if line.strip().startswith("-")]
    assert all("compose/apps/overrides/base.yml" not in line for line in listed_lines)
