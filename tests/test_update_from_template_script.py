import os
import shutil
import subprocess
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = REPO_ROOT / "scripts" / "update_from_template.sh"


def run(cmd, cwd):
    subprocess.run(cmd, cwd=cwd, check=True)


def create_consumer_repo(tmp_path):
    consumer = tmp_path / "consumer"
    scripts_dir = consumer / "scripts"
    scripts_dir.mkdir(parents=True)
    shutil.copy2(SCRIPT_PATH, scripts_dir / "update_from_template.sh")

    run(["git", "init"], cwd=consumer)
    run(["git", "config", "user.email", "ci@example.com"], cwd=consumer)
    run(["git", "config", "user.name", "CI"], cwd=consumer)

    (consumer / "base.txt").write_text("template base\n", encoding="utf-8")
    run(["git", "add", "base.txt"], cwd=consumer)
    run(["git", "commit", "-m", "Template base"], cwd=consumer)

    return consumer


def test_script_requires_remote_argument(tmp_path):
    consumer = create_consumer_repo(tmp_path)
    script = consumer / "scripts" / "update_from_template.sh"
    os.chmod(script, 0o755)

    result = subprocess.run(
        [str(script)],
        cwd=consumer,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode != 0
    assert "remote do template não informado" in result.stderr


def test_dry_run_outputs_expected_commands(tmp_path):
    template_remote = tmp_path / "template.git"
    run(["git", "init", "--bare", str(template_remote)], cwd=tmp_path)
    subprocess.run(
        ["git", "--git-dir", str(template_remote), "symbolic-ref", "HEAD", "refs/heads/main"],
        check=True,
    )

    consumer = create_consumer_repo(tmp_path)
    script = consumer / "scripts" / "update_from_template.sh"
    os.chmod(script, 0o755)

    original_commit = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=consumer,
        text=True,
        capture_output=True,
        check=True,
    ).stdout.strip()

    run(["git", "remote", "add", "template", str(template_remote)], cwd=consumer)
    run(["git", "branch", "-M", "main"], cwd=consumer)
    run(["git", "push", "template", "main"], cwd=consumer)

    template_work = tmp_path / "template-work"
    run(["git", "clone", str(template_remote), str(template_work)] , cwd=tmp_path)
    run(["git", "config", "user.email", "ci@example.com"], cwd=template_work)
    run(["git", "config", "user.name", "CI"], cwd=template_work)
    (template_work / "base.txt").write_text("template base\nupstream change\n", encoding="utf-8")
    run(["git", "add", "base.txt"], cwd=template_work)
    run(["git", "commit", "-m", "Upstream update"], cwd=template_work)
    run(["git", "push", "origin", "main"], cwd=template_work)

    (consumer / "local.txt").write_text("local change\n", encoding="utf-8")
    run(["git", "add", "local.txt"], cwd=consumer)
    run(["git", "commit", "-m", "Local customization"], cwd=consumer)

    first_commit = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=consumer,
        text=True,
        capture_output=True,
        check=True,
    ).stdout.strip()

    env = {
        **os.environ,
        "TEMPLATE_REMOTE": "template",
        "ORIGINAL_COMMIT_ID": original_commit,
        "FIRST_COMMIT_ID": first_commit,
        "TARGET_BRANCH": "main",
    }

    result = subprocess.run(
        [str(script), "--dry-run"],
        cwd=consumer,
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )

    assert result.returncode == 0
    assert "Modo dry-run habilitado" in result.stdout
    assert "git fetch template main" in result.stdout
    assert "git rebase --onto template/main" in result.stdout
