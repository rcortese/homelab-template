import os
import shutil
import subprocess
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[3]
SCRIPT_PATH = REPO_ROOT / "scripts" / "update_from_template.sh"


def run(cmd, cwd):
    subprocess.run(cmd, cwd=cwd, check=True)


def create_consumer_repo(tmp_path):
    consumer = tmp_path / "consumer"
    scripts_dir = consumer / "scripts"
    scripts_dir.mkdir(parents=True)
    shutil.copy2(SCRIPT_PATH, scripts_dir / "update_from_template.sh")
    shutil.copytree(
        REPO_ROOT / "scripts" / "lib",
        scripts_dir / "lib",
        dirs_exist_ok=True,
    )

    run(["git", "init"], cwd=consumer)
    run(["git", "config", "user.email", "ci@example.com"], cwd=consumer)
    run(["git", "config", "user.name", "CI"], cwd=consumer)

    (consumer / "base.txt").write_text("template base\n", encoding="utf-8")
    run(
        ["git", "add", "base.txt", "scripts/update_from_template.sh", "scripts/lib"],
        cwd=consumer,
    )
    run(["git", "commit", "-m", "Template base"], cwd=consumer)

    return consumer


def setup_template_remote(tmp_path):
    template_remote = tmp_path / "template.git"
    run(["git", "init", "--bare", str(template_remote)], cwd=tmp_path)
    subprocess.run(
        ["git", "--git-dir", str(template_remote), "symbolic-ref", "HEAD", "refs/heads/main"],
        check=True,
    )

    def clone_worktree(name="template-work"):
        template_work = tmp_path / name
        run(["git", "clone", str(template_remote), str(template_work)], cwd=tmp_path)
        run(["git", "config", "user.email", "ci@example.com"], cwd=template_work)
        run(["git", "config", "user.name", "CI"], cwd=template_work)
        return template_work

    return template_remote, clone_worktree


def test_require_interactive_input_fallback_without_error_helper(tmp_path):
    script = tmp_path / "check_require.sh"
    script.write_text(
        """#!/usr/bin/env bash
source \"{lib_path}\"
require_interactive_input \"interação obrigatória não disponível\"
exit $?
""".format(lib_path=REPO_ROOT / "scripts" / "lib" / "template_prompts.sh"),
        encoding="utf-8",
    )
    os.chmod(script, 0o755)

    result = subprocess.run(
        [str(script)], capture_output=True, text=True, check=False
    )

    assert result.returncode != 0
    assert "interação obrigatória não disponível" in result.stderr


def test_require_interactive_input_returns_error_when_helper_does_not_exit(tmp_path):
    script = tmp_path / "check_require_with_error.sh"
    script.write_text(
        f"""#!/usr/bin/env bash
error() {{
  echo "[error] $1" >&2
  return 0
}}
source "{REPO_ROOT / "scripts" / "lib" / "template_prompts.sh"}"
require_interactive_input "entrada interativa necessária"
exit $?
""",
        encoding="utf-8",
    )
    os.chmod(script, 0o755)

    result = subprocess.run(
        [str(script)], capture_output=True, text=True, check=False
    )

    assert result.returncode != 0
    assert "[error] entrada interativa necessária" in result.stderr


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
    template_remote, clone_template_remote = setup_template_remote(tmp_path)

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

    template_work = clone_template_remote()
    run(["git", "fetch", "origin", "main"], cwd=template_work)
    run(["git", "checkout", "-B", "main", "origin/main"], cwd=template_work)
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
    assert first_commit in result.stdout
    assert f"git rebase --onto template/main {first_commit}^ main" in result.stdout


def test_script_fails_with_pending_changes(tmp_path):
    template_remote, _ = setup_template_remote(tmp_path)

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

    # Introduz uma alteração não commitada
    (consumer / "local.txt").write_text("local change\nmodificação pendente\n", encoding="utf-8")

    env = {
        **os.environ,
        "TEMPLATE_REMOTE": "template",
        "ORIGINAL_COMMIT_ID": original_commit,
        "FIRST_COMMIT_ID": first_commit,
        "TARGET_BRANCH": "main",
    }

    result = subprocess.run(
        [str(script)],
        cwd=consumer,
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )

    assert result.returncode != 0
    assert "alterações locais não commitadas" in result.stderr


def test_script_errors_when_remote_missing(tmp_path):
    consumer = create_consumer_repo(tmp_path)
    script = consumer / "scripts" / "update_from_template.sh"
    os.chmod(script, 0o755)

    head_commit = (
        subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=consumer,
            text=True,
            capture_output=True,
            check=True,
        ).stdout.strip()
    )

    env = {
        **os.environ,
        "TEMPLATE_REMOTE": "missing",
        "ORIGINAL_COMMIT_ID": head_commit,
        "FIRST_COMMIT_ID": head_commit,
        "TARGET_BRANCH": "main",
    }

    result = subprocess.run(
        [str(script)],
        cwd=consumer,
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )

    assert result.returncode != 0
    assert "remote 'missing' não está configurado" in result.stderr


def test_script_errors_when_target_branch_missing(tmp_path):
    template_remote, _ = setup_template_remote(tmp_path)

    consumer = create_consumer_repo(tmp_path)
    script = consumer / "scripts" / "update_from_template.sh"
    os.chmod(script, 0o755)

    head_commit = (
        subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=consumer,
            text=True,
            capture_output=True,
            check=True,
        ).stdout.strip()
    )

    run(["git", "remote", "add", "template", str(template_remote)], cwd=consumer)

    env = {
        **os.environ,
        "TEMPLATE_REMOTE": "template",
        "ORIGINAL_COMMIT_ID": head_commit,
        "FIRST_COMMIT_ID": head_commit,
        "TARGET_BRANCH": "nonexistent",
    }

    result = subprocess.run(
        [str(script)],
        cwd=consumer,
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )

    assert result.returncode != 0
    assert "branch 'nonexistent' não encontrado no remote 'template'" in result.stderr


def test_script_errors_when_original_commit_is_invalid(tmp_path):
    consumer = create_consumer_repo(tmp_path)
    script = consumer / "scripts" / "update_from_template.sh"
    os.chmod(script, 0o755)

    head_commit = (
        subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=consumer,
            text=True,
            capture_output=True,
            check=True,
        ).stdout.strip()
    )

    env = {
        **os.environ,
        "TEMPLATE_REMOTE": "template",
        "ORIGINAL_COMMIT_ID": "deadbeef",
        "FIRST_COMMIT_ID": head_commit,
        "TARGET_BRANCH": "main",
    }

    result = subprocess.run(
        [str(script)],
        cwd=consumer,
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )

    assert result.returncode != 0
    assert "commit original deadbeef não foi encontrado" in result.stderr


def test_script_errors_when_first_commit_not_descends_from_original(tmp_path):
    template_remote, _ = setup_template_remote(tmp_path)

    consumer = create_consumer_repo(tmp_path)
    script = consumer / "scripts" / "update_from_template.sh"
    os.chmod(script, 0o755)

    run(["git", "branch", "-M", "main"], cwd=consumer)
    run(["git", "remote", "add", "template", str(template_remote)], cwd=consumer)
    run(["git", "push", "template", "main"], cwd=consumer)

    (consumer / "local.txt").write_text("local change\n", encoding="utf-8")
    run(["git", "add", "local.txt"], cwd=consumer)
    run(["git", "commit", "-m", "Local customization"], cwd=consumer)

    first_commit = (
        subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=consumer,
            text=True,
            capture_output=True,
            check=True,
        ).stdout.strip()
    )

    base_commit = (
        subprocess.run(
            ["git", "rev-parse", "HEAD~1"],
            cwd=consumer,
            text=True,
            capture_output=True,
            check=True,
        ).stdout.strip()
    )

    run(["git", "checkout", "-b", "side", base_commit], cwd=consumer)
    (consumer / "side.txt").write_text("side branch\n", encoding="utf-8")
    run(["git", "add", "side.txt"], cwd=consumer)
    run(["git", "commit", "-m", "Side commit"], cwd=consumer)

    original_commit = (
        subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=consumer,
            text=True,
            capture_output=True,
            check=True,
        ).stdout.strip()
    )

    run(["git", "checkout", "main"], cwd=consumer)

    env = {
        **os.environ,
        "TEMPLATE_REMOTE": "template",
        "ORIGINAL_COMMIT_ID": original_commit,
        "FIRST_COMMIT_ID": first_commit,
        "TARGET_BRANCH": "main",
    }

    result = subprocess.run(
        [str(script)],
        cwd=consumer,
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )

    assert result.returncode != 0
    assert (
        f"o commit {original_commit} não é ancestral de {first_commit}" in result.stderr
    )
