import os
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[3]
SCRIPT_PATH = REPO_ROOT / "scripts" / "detect_template_commits.sh"


def bootstrap_consumer_repository(tmp_path):
    template_remote = tmp_path / "template.git"
    run(["git", "init", "--bare", str(template_remote)], cwd=tmp_path)
    subprocess.run(
        [
            "git",
            "--git-dir",
            str(template_remote),
            "symbolic-ref",
            "HEAD",
            "refs/heads/main",
        ],
        check=True,
    )

    template_work = tmp_path / "template-work"
    run(["git", "clone", str(template_remote), str(template_work)], cwd=tmp_path)
    run(["git", "config", "user.email", "ci@example.com"], cwd=template_work)
    run(["git", "config", "user.name", "CI"], cwd=template_work)

    base_file = template_work / "base.txt"
    base_file.write_text("template base\n", encoding="utf-8")
    run(["git", "add", "base.txt"], cwd=template_work)
    run(["git", "commit", "-m", "Template base"], cwd=template_work)
    run(["git", "push", "origin", "main"], cwd=template_work)

    consumer = tmp_path / "consumer"
    run(["git", "clone", str(template_remote), str(consumer)], cwd=tmp_path)
    run(["git", "config", "user.email", "ci@example.com"], cwd=consumer)
    run(["git", "config", "user.name", "CI"], cwd=consumer)

    scripts_dir = consumer / "scripts"
    scripts_dir.mkdir()
    shutil.copy2(SCRIPT_PATH, scripts_dir / "detect_template_commits.sh")
    shutil.copytree(
        REPO_ROOT / "scripts" / "lib",
        scripts_dir / "lib",
        dirs_exist_ok=True,
    )

    (consumer / "local.txt").write_text("local change\n", encoding="utf-8")
    run(["git", "add", "local.txt"], cwd=consumer)
    run(["git", "commit", "-m", "Local customization"], cwd=consumer)

    remote_name = (
        subprocess.run(
            ["git", "remote"],
            cwd=consumer,
            text=True,
            capture_output=True,
            check=True,
        )
        .stdout.strip()
        .splitlines()[0]
    )

    original_commit = (
        subprocess.run(
            ["git", "merge-base", "HEAD", f"{remote_name}/main"],
            cwd=consumer,
            text=True,
            capture_output=True,
            check=True,
        ).stdout.strip()
    )

    first_commit = (
        subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=consumer,
            text=True,
            capture_output=True,
            check=True,
        ).stdout.strip()
    )

    script = scripts_dir / "detect_template_commits.sh"
    os.chmod(script, 0o755)

    return consumer, script, remote_name, original_commit, first_commit


def prepare_script_tree(tmp_path):
    repo_root = tmp_path / "workspace"
    scripts_dir = repo_root / "scripts"
    scripts_dir.mkdir(parents=True)
    shutil.copy2(SCRIPT_PATH, scripts_dir / "detect_template_commits.sh")
    shutil.copytree(
        REPO_ROOT / "scripts" / "lib",
        scripts_dir / "lib",
        dirs_exist_ok=True,
    )
    script_path = scripts_dir / "detect_template_commits.sh"
    os.chmod(script_path, 0o755)
    return repo_root, script_path


def run(cmd, cwd):
    subprocess.run(cmd, cwd=cwd, check=True)


@pytest.mark.parametrize("flag", ["-h", "--help"])
def test_detect_template_commits_help_flags(tmp_path, flag):
    repo_root, script = prepare_script_tree(tmp_path)

    result = subprocess.run(
        [str(script), flag],
        cwd=repo_root,
        text=True,
        capture_output=True,
        check=False,
        env=os.environ,
    )

    assert result.returncode == 0
    assert "Usage: scripts/detect_template_commits.sh [options]" in result.stdout
    assert "-h, --help" in result.stdout


@pytest.mark.parametrize(
    "args, expected_error",
    [
        (["--remote"], "--remote requires an argument."),
        (["--unknown"], "unknown argument: --unknown"),
    ],
)
def test_detect_template_commits_argument_errors(tmp_path, args, expected_error):
    repo_root, script = prepare_script_tree(tmp_path)

    result = subprocess.run(
        [str(script), *args],
        cwd=repo_root,
        text=True,
        capture_output=True,
        check=False,
        env=os.environ,
    )

    assert result.returncode != 0
    assert expected_error in result.stderr


def test_detect_template_commits_generates_file(tmp_path):
    consumer, script, remote_name, original_commit, first_commit = bootstrap_consumer_repository(tmp_path)

    result = subprocess.run(
        [str(script)],
        cwd=consumer,
        text=True,
        capture_output=True,
        check=False,
        env=os.environ,
    )

    assert result.returncode == 0
    assert f"ORIGINAL_COMMIT_ID={original_commit}" in result.stdout
    assert f"FIRST_COMMIT_ID={first_commit}" in result.stdout

    output_file = consumer / "env" / "local" / "template_commits.env"
    assert output_file.exists()
    content = output_file.read_text(encoding="utf-8")
    assert f"ORIGINAL_COMMIT_ID={original_commit}" in content
    assert f"FIRST_COMMIT_ID={first_commit}" in content


def test_detect_template_commits_respects_custom_output(tmp_path):
    consumer, script, _, original_commit, first_commit = bootstrap_consumer_repository(tmp_path)
    custom_output = consumer / "custom" / "template_commits.env"

    result = subprocess.run(
        [str(script), "--output", str(custom_output)],
        cwd=consumer,
        text=True,
        capture_output=True,
        check=False,
        env=os.environ,
    )

    assert result.returncode == 0
    assert f"ORIGINAL_COMMIT_ID={original_commit}" in result.stdout
    assert f"FIRST_COMMIT_ID={first_commit}" in result.stdout
    assert f"Values saved to: {custom_output}" in result.stdout

    assert custom_output.exists()
    content = custom_output.read_text(encoding="utf-8")
    assert f"ORIGINAL_COMMIT_ID={original_commit}" in content
    assert f"FIRST_COMMIT_ID={first_commit}" in content


def create_git_stub(tmp_path):
    stub_dir = tmp_path / "git-stub"
    stub_dir.mkdir(exist_ok=True)
    log_file = tmp_path / "git-stub.log"
    real_git = shutil.which("git")

    stub_script = stub_dir / "git"
    stub_script.write_text(
        "#!/usr/bin/env bash\n"
        "set -euo pipefail\n"
        "printf '%s\\n' \"$*\" >>\"$GIT_STUB_LOG\"\n"
        "exec \"$REAL_GIT\" \"$@\"\n",
        encoding="utf-8",
    )
    os.chmod(stub_script, 0o755)

    env = os.environ.copy()
    env.update(
        {
            "PATH": f"{stub_dir}:{env['PATH']}",
            "REAL_GIT": real_git,
            "GIT_STUB_LOG": str(log_file),
        }
    )

    return env, log_file


def test_detect_template_commits_no_fetch_skips_fetch_invocation(tmp_path):
    consumer, script, remote_name, original_commit, first_commit = bootstrap_consumer_repository(tmp_path)
    env, log_file = create_git_stub(tmp_path)

    # PATH prioritizes our stub so the test can observe which git subcommands are
    # executed, while REAL_GIT keeps merge-base, rev-list e afins funcionando
    # ao delegar para o binário real.
    result = subprocess.run(
        [
            str(script),
            "--remote",
            remote_name,
            "--target-branch",
            "main",
            "--no-fetch",
        ],
        cwd=consumer,
        text=True,
        capture_output=True,
        check=False,
        env=env,
    )

    assert result.returncode == 0
    assert f"ORIGINAL_COMMIT_ID={original_commit}" in result.stdout
    assert f"FIRST_COMMIT_ID={first_commit}" in result.stdout

    assert log_file.exists()
    log_lines = [line.strip() for line in log_file.read_text(encoding="utf-8").splitlines() if line.strip()]
    assert log_lines, "expected git stub to record executed subcommands"
    assert all(line.split()[0] != "fetch" for line in log_lines)


def test_detect_template_commits_runs_fetch_by_default(tmp_path):
    consumer, script, remote_name, original_commit, first_commit = bootstrap_consumer_repository(tmp_path)
    env, log_file = create_git_stub(tmp_path)

    result = subprocess.run(
        [
            str(script),
            "--remote",
            remote_name,
            "--target-branch",
            "main",
        ],
        cwd=consumer,
        text=True,
        capture_output=True,
        check=False,
        env=env,
    )

    assert result.returncode == 0
    assert f"ORIGINAL_COMMIT_ID={original_commit}" in result.stdout
    assert f"FIRST_COMMIT_ID={first_commit}" in result.stdout

    assert log_file.exists()
    log_lines = [line.strip() for line in log_file.read_text(encoding="utf-8").splitlines() if line.strip()]
    assert log_lines, "expected git stub to record executed subcommands"
    assert any(line.split()[0] == "fetch" for line in log_lines), "expected git fetch to be invoked"


def test_detect_template_commits_fails_outside_git_repo(tmp_path):
    repo_root, script = prepare_script_tree(tmp_path)

    result = subprocess.run(
        [str(script)],
        cwd=repo_root,
        text=True,
        capture_output=True,
        check=False,
        env=os.environ,
    )

    assert result.returncode != 0
    assert "este diretório não é um repositório Git." in result.stderr


def test_detect_template_commits_fails_with_missing_remote(tmp_path):
    repo_root, script = prepare_script_tree(tmp_path)
    run(["git", "init"], cwd=repo_root)

    result = subprocess.run(
        [str(script), "--remote", "nonexistent"],
        cwd=repo_root,
        text=True,
        capture_output=True,
        check=False,
        env=os.environ,
    )

    assert result.returncode != 0
    assert "remote 'nonexistent' não está configurado." in result.stderr


def test_detect_template_commits_fails_with_missing_target_branch(tmp_path):
    repo_root, script = prepare_script_tree(tmp_path)
    run(["git", "init"], cwd=repo_root)

    remote_path = tmp_path / "remote.git"
    run(["git", "init", "--bare", str(remote_path)], cwd=tmp_path)
    run(["git", "remote", "add", "origin", str(remote_path)], cwd=repo_root)

    result = subprocess.run(
        [str(script), "--remote", "origin", "--target-branch", "main"],
        cwd=repo_root,
        text=True,
        capture_output=True,
        check=False,
        env=os.environ,
    )

    assert result.returncode != 0
    assert "branch 'main' não encontrado no remote 'origin'." in result.stderr
