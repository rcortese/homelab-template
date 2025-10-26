from __future__ import annotations

import os
from pathlib import Path

from .utils import run_backup


def _install_compose_stub(repo_copy: Path) -> Path:
    compose_log = repo_copy / "compose_calls.log"
    compose_stub = repo_copy / "scripts" / "compose.sh"
    compose_stub.write_text(
        f"""#!/usr/bin/env bash\nset -euo pipefail\nprintf '%s\\n' \"$*\" >> {compose_log!s}\n""",
        encoding="utf-8",
    )
    compose_stub.chmod(0o755)
    return compose_log


def _prepend_fake_bin(
    repo_copy: Path, monkeypatch, *binaries: tuple[str, str]
) -> tuple[Path, str]:
    fake_bin = repo_copy / ".fake-bin"
    fake_bin.mkdir(exist_ok=True)
    for name, script_body in binaries:
        target = fake_bin / name
        target.write_text(script_body, encoding="utf-8")
        target.chmod(0o755)
    original_path = os.environ.get("PATH", "")
    monkeypatch.setenv("PATH", f"{fake_bin}{os.pathsep}{original_path}")
    return fake_bin, original_path


def test_successful_backup_creates_snapshot_and_restarts_stack(
    repo_copy: Path, monkeypatch
) -> None:
    compose_log = _install_compose_stub(repo_copy)
    _prepend_fake_bin(
        repo_copy,
        monkeypatch,
        (
            "date",
            "#!/usr/bin/env bash\nset -euo pipefail\nprintf '20240101-030405\\n'\n",
        ),
    )

    data_dir = repo_copy / "data" / "app-core"
    data_dir.mkdir(parents=True)
    (data_dir / "db.sqlite").write_text("payload", encoding="utf-8")

    result = run_backup(repo_copy, "core")

    assert result.returncode == 0, result.stderr
    assert "Backup da instância 'core' concluído" in result.stdout

    backup_dir = repo_copy / "backups" / "core-20240101-030405"
    assert backup_dir.is_dir()
    assert (backup_dir / "db.sqlite").read_text(encoding="utf-8") == "payload"

    calls = compose_log.read_text(encoding="utf-8").splitlines()
    assert calls == ["core down", "core up -d"]


def test_copy_failure_still_attempts_restart(repo_copy: Path, monkeypatch) -> None:
    compose_log = _install_compose_stub(repo_copy)
    cp_log = repo_copy / "cp_calls.log"
    fake_bin, original_path = _prepend_fake_bin(
        repo_copy,
        monkeypatch,
        (
            "date",
            "#!/usr/bin/env bash\nset -euo pipefail\nprintf '20240101-030405\\n'\n",
        ),
        (
            "cp",
            "#!/usr/bin/env bash\nprintf '%s\\n' \"$@\" >> {log}\necho 'stub copy failure' >&2\nexit 1\n".format(
                log=cp_log
            ),
        ),
    )

    data_dir = repo_copy / "data" / "app-core"
    data_dir.mkdir(parents=True)
    (data_dir / "db.sqlite").write_text("payload", encoding="utf-8")

    result = run_backup(repo_copy, "core")

    assert result.returncode == 1
    assert "Falha ao copiar os dados" in result.stderr

    backup_dir = repo_copy / "backups" / "core-20240101-030405"
    assert backup_dir.is_dir()
    assert list(backup_dir.iterdir()) == []

    calls = compose_log.read_text(encoding="utf-8").splitlines()
    assert calls == ["core down", "core up -d"]
    assert cp_log.read_text(encoding="utf-8").splitlines() == [
        "-a",
        f"{repo_copy}/data/app-core/.",
        f"{repo_copy}/backups/core-20240101-030405/",
    ]

    # Restore PATH to avoid leaking stubs into other tests
    monkeypatch.setenv("PATH", original_path)
    for stub in fake_bin.iterdir():
        stub.unlink()
    fake_bin.rmdir()
