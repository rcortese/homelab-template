import os
import subprocess
from pathlib import Path


def _snapshot_tree(root: Path) -> tuple[set[Path], set[Path]]:
    directories: set[Path] = set()
    files: set[Path] = set()

    for entry in root.rglob("*"):
        relative = entry.relative_to(root)
        if entry.is_dir():
            directories.add(relative)
        else:
            files.add(relative)

    return directories, files


def _append_env_values(env_file: Path, *, data_dir: str | None = None, uid: int | None = None, gid: int | None = None) -> None:
    current = env_file.read_text(encoding="utf-8")
    lines: list[str] = []
    if data_dir is not None:
        lines.append(f"APP_DATA_DIR={data_dir}\n")
    if uid is not None:
        lines.append(f"APP_DATA_UID={uid}\n")
    if gid is not None:
        lines.append(f"APP_DATA_GID={gid}\n")
    env_file.write_text(current + "".join(lines), encoding="utf-8")


def _run_script(repo_root: Path, *args: str) -> subprocess.CompletedProcess[str]:
    script = repo_root / "scripts" / "fix_permission_issues.sh"
    return subprocess.run(
        ["bash", str(script), *args],
        cwd=repo_root,
        capture_output=True,
        text=True,
        check=False,
    )


def _current_ids() -> tuple[int, int]:
    uid = os.getuid() if hasattr(os, "getuid") else 1000
    gid = os.getgid() if hasattr(os, "getgid") else 1000
    return uid, gid


def test_dry_run_outputs_planned_actions(repo_copy: Path) -> None:
    env_file = repo_copy / "env" / "local" / "core.env"
    uid, gid = _current_ids()
    _append_env_values(env_file, uid=uid, gid=gid)

    data_dir = repo_copy / "data" / "app-core"
    backups_dir = repo_copy / "backups"
    expected_dirs = (data_dir, backups_dir)

    pre_existing = {directory: directory.exists() for directory in expected_dirs}
    pre_contents: dict[Path, list[Path]] = {}
    pre_stats: dict[Path, os.stat_result] = {}

    for directory, exists in pre_existing.items():
        if exists:
            pre_contents[directory] = sorted(
                child.relative_to(directory) for child in directory.rglob("*")
            )
            if hasattr(os, "getuid"):
                pre_stats[directory] = directory.stat()
        else:
            assert not directory.exists(), f"{directory} deveria estar ausente antes do dry-run"

    pre_dirs_snapshot, pre_files_snapshot = _snapshot_tree(repo_copy)

    result = _run_script(repo_copy, "core", "--dry-run")

    assert result.returncode == 0, result.stderr
    stdout = result.stdout

    owner = f"{uid}:{gid}"

    assert "[*] Instância: core" in stdout
    assert f"mkdir -p {data_dir}" in stdout
    assert f"mkdir -p {backups_dir}" in stdout
    assert f"chown {owner} {data_dir} {backups_dir}" in stdout

    post_dirs_snapshot, post_files_snapshot = _snapshot_tree(repo_copy)
    assert post_dirs_snapshot == pre_dirs_snapshot
    assert post_files_snapshot == pre_files_snapshot

    for directory, existed_before in pre_existing.items():
        if existed_before:
            assert directory.exists(), f"{directory} deveria permanecer existente após o dry-run"
            post_contents = sorted(child.relative_to(directory) for child in directory.rglob("*"))
            assert post_contents == pre_contents[directory]
            if hasattr(os, "getuid") and directory in pre_stats:
                stats = directory.stat()
                previous_stats = pre_stats[directory]
                assert stats.st_uid == previous_stats.st_uid
                assert stats.st_gid == previous_stats.st_gid
        else:
            assert not directory.exists(), f"{directory} não deveria ser criado em um dry-run"


def test_script_creates_directories_and_applies_owner(repo_copy: Path) -> None:
    env_file = repo_copy / "env" / "local" / "core.env"
    uid, gid = _current_ids()
    _append_env_values(env_file, data_dir="custom-storage", uid=uid, gid=gid)

    result = _run_script(repo_copy, "core")

    assert result.returncode == 0, result.stderr
    stdout = result.stdout

    data_dir = repo_copy / "custom-storage"
    backups_dir = repo_copy / "backups"

    assert data_dir.is_dir()
    assert backups_dir.is_dir()

    if hasattr(os, "getuid"):
        data_stat = data_dir.stat()
        backups_stat = backups_dir.stat()
        assert data_stat.st_uid == uid
        assert data_stat.st_gid == gid
        assert backups_stat.st_uid == uid
        assert backups_stat.st_gid == gid

    assert "Correções de permissão concluídas" in stdout
