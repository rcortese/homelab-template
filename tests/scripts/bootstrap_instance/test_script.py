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
    assert "[*] Bootstrap completed successfully." in stdout

    instance_file = repo_copy / "compose" / "docker-compose.staging.yml"
    env_file = repo_copy / "env" / "staging.example.env"
    doc_file = repo_copy / "docs" / "apps" / "analytics.md"
    docs_readme = repo_copy / "docs" / "README.md"

    assert instance_file.is_file()
    assert env_file.is_file()
    assert doc_file.is_file()

    instance_content = instance_file.read_text(encoding="utf-8")
    env_content = env_file.read_text(encoding="utf-8")
    doc_content = doc_file.read_text(encoding="utf-8")

    assert "container_name" not in instance_content
    assert "${ANALYTICS_STAGING_PORT:-8080}" in instance_content
    assert "APP_PUBLIC_URL" in instance_content

    assert "ANALYTICS_STAGING_PORT=8080" in env_content
    assert "SERVICE_NAME" not in env_content

    assert "# Analytics (analytics)" in doc_content
    assert "compose/docker-compose.staging.yml" in doc_content
    assert "env/staging.example.env" in doc_content

    docs_index = docs_readme.read_text(encoding="utf-8")
    assert "## Applications" in docs_index
    assert "[Analytics](./apps/analytics.md)" in docs_index


def test_fails_when_targets_exist(repo_copy: Path) -> None:
    compose_file = repo_copy / "compose" / "docker-compose.demo.yml"
    compose_file.parent.mkdir(parents=True)
    compose_file.write_text("services: {}\n", encoding="utf-8")

    result = _run_bootstrap(repo_copy, "existing", "demo")

    assert result.returncode == 1
    stderr = result.stderr
    assert "already exist" in stderr
    assert str(compose_file) in stderr

    instance_file = repo_copy / "compose" / "docker-compose.demo.yml"
    env_file = repo_copy / "env" / "demo.example.env"

    assert instance_file.exists()
    assert not env_file.exists()


def test_accepts_custom_base_dir(repo_copy: Path) -> None:
    scripts_dir = repo_copy / "scripts"
    result = _run_bootstrap(repo_copy, "demo", "qa", "--base-dir", str(repo_copy), cwd=scripts_dir)

    assert result.returncode == 0, result.stderr

    instance_file = repo_copy / "compose" / "docker-compose.qa.yml"
    env_file = repo_copy / "env" / "qa.example.env"

    assert instance_file.is_file()
    assert env_file.is_file()

def test_existing_env_file_is_preserved(repo_copy: Path) -> None:
    instance_name = "existingenv"
    env_file = repo_copy / "env" / f"{instance_name}.example.env"
    env_file.parent.mkdir(parents=True, exist_ok=True)
    sentinel_content = "SENTINEL_ENV=1\n"
    env_file.write_text(sentinel_content, encoding="utf-8")

    app_name = "preserve"
    result = _run_bootstrap(repo_copy, app_name, instance_name)

    assert result.returncode == 0, result.stderr
    stdout = result.stdout
    assert "keeping unchanged" in stdout

    assert env_file.read_text(encoding="utf-8") == sentinel_content

    instance_file = repo_copy / "compose" / f"docker-compose.{instance_name}.yml"

    assert instance_file.is_file()

    listed_lines = [line.strip() for line in stdout.splitlines() if line.strip().startswith("-")]
    assert any(f"compose/docker-compose.{instance_name}.yml" in line for line in listed_lines)


@pytest.mark.parametrize(
    "app_name, instance_name, expected_message",
    [
        ("-demo", "valid", "Error: Application name"),
        ("Invalid", "valid", "Error: Application name"),
        ("demo", "-invalid", "Error: Instance name"),
        ("demo", "Invalid", "Error: Instance name"),
    ],
)
def test_rejects_invalid_names(
    repo_copy: Path, app_name: str, instance_name: str, expected_message: str
) -> None:
    result = _run_bootstrap(repo_copy, app_name, instance_name)

    assert result.returncode == 1
    stderr = result.stderr
    assert expected_message in stderr
