from __future__ import annotations

import os
from pathlib import Path

from tests.helpers.compose_instances import ComposeInstancesData

from .utils import run_backup


def _assert_restart_apps(stdout: str, expected_apps: list[str]) -> None:
    if expected_apps:
        line = next(
            (
                entry
                for entry in stdout.splitlines()
                if "Aplicações detectadas para religar:" in entry
            ),
            None,
        )
        assert line is not None, f"Linha com aplicações não encontrada em: {stdout!r}"
        _, _, tail = line.partition(":")
        apps = tail.strip().split()
        assert apps == expected_apps
    else:
        assert (
            "Nenhuma aplicação ativa identificada; nenhum serviço será religado." in stdout
        ), f"Mensagem de ausência de serviços não encontrada em: {stdout!r}"
        assert (
            "Aplicações detectadas para religar:" not in stdout
        ), "Mensagem inesperada de aplicações detectadas encontrada"


def _install_compose_stub(
    repo_copy: Path,
    running_services: dict[str, list[str]] | None = None,
    up_fail_instances: set[str] | None = None,
) -> Path:
    compose_log = repo_copy / "compose_calls.log"
    compose_stub = repo_copy / "scripts" / "compose.sh"
    running_services = running_services or {}
    up_fail_instances = up_fail_instances or set()
    fail_file = repo_copy / "compose_up_failures"
    fail_file.write_text("\n".join(sorted(up_fail_instances)), encoding="utf-8")
    case_entries: list[str] = []
    for instance, services in running_services.items():
        case_entries.append(f"    {instance})")
        for service in services:
            case_entries.append(f"      printf '%s\\n' \"{service}\"")
        case_entries.append("      ;;")
    case_entries.append("    * ) ;;")
    case_block = "\n".join(case_entries)
    compose_stub.write_text(
        "\n".join(
            [
                "#!/usr/bin/env bash",
                "set -euo pipefail",
                f"printf '%s\\n' \"$*\" >> {compose_log!s}",
                "instance=\"$1\"",
                "shift || true",
                "command=\"${1:-}\"",
                f"fail_file=\"{fail_file!s}\"",
                "if [[ \"${1:-}\" == 'ps' && \"${2:-}\" == '--status' && \"${3:-}\" == 'running' && \"${4:-}\" == '--services' ]]; then",
                "  case \"$instance\" in",
                case_block,
                "  esac",
                "fi",
                "if [[ \"$command\" == 'up' ]]; then",
                "  if [[ -n \"$fail_file\" && -f \"$fail_file\" ]] && grep -Fxq \"$instance\" \"$fail_file\"; then",
                "    echo 'stub compose up failure' >&2",
                "    exit 1",
                "  fi",
                "fi",
            ]
        )
        + "\n",
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


def _assert_compose_restart_calls(
    compose_log: Path, expected_apps: list[str]
) -> None:
    calls = compose_log.read_text(encoding="utf-8").splitlines()
    assert calls[:2] == [
        "core ps --status running --services",
        "core down",
    ]
    if expected_apps:
        assert len(calls) >= 3
        third_command = calls[2]
        assert third_command.startswith("core up -d ")
        actual_apps = third_command.split()[3:]
        assert actual_apps == expected_apps
    else:
        assert all(not entry.startswith("core up -d") for entry in calls[2:])


def test_successful_backup_creates_snapshot_and_restarts_stack(
    repo_copy: Path,
    monkeypatch,
    compose_instances_data: ComposeInstancesData,
) -> None:
    expected_core_apps = compose_instances_data.instance_app_names.get("core", [])
    compose_log = _install_compose_stub(
        repo_copy,
        {"core": expected_core_apps},
    )
    _prepend_fake_bin(
        repo_copy,
        monkeypatch,
        (
            "date",
            "#!/usr/bin/env bash\nset -euo pipefail\nprintf '20240101-030405\\n'\n",
        ),
    )

    env_file = repo_copy / "env" / "local" / "core.env"
    env_file.write_text(
        env_file.read_text(encoding="utf-8") + "APP_DATA_DIR=data/core-root\n",
        encoding="utf-8",
    )

    data_mount = repo_copy / "data" / "core-root" / "app-core"
    data_mount.mkdir(parents=True)
    (data_mount / "db.sqlite").write_text("payload", encoding="utf-8")

    result = run_backup(repo_copy, "core")

    assert result.returncode == 0, result.stderr
    assert "Backup da instância 'core' concluído" in result.stdout
    _assert_restart_apps(result.stdout, expected_core_apps)

    backup_dir = repo_copy / "backups" / "core-20240101-030405"
    assert backup_dir.is_dir()
    restored_file = backup_dir / "db.sqlite"
    assert restored_file.read_text(encoding="utf-8") == "payload"

    _assert_compose_restart_calls(compose_log, expected_core_apps)


def test_copy_failure_still_attempts_restart(
    repo_copy: Path,
    monkeypatch,
    compose_instances_data: ComposeInstancesData,
) -> None:
    expected_core_apps = compose_instances_data.instance_app_names.get("core", [])
    compose_log = _install_compose_stub(
        repo_copy,
        {"core": expected_core_apps},
    )
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

    env_file = repo_copy / "env" / "local" / "core.env"
    env_file.write_text(
        env_file.read_text(encoding="utf-8") + "APP_DATA_DIR=data/core-root\n",
        encoding="utf-8",
    )

    data_mount = repo_copy / "data" / "core-root" / "app-core"
    data_mount.mkdir(parents=True)
    (data_mount / "db.sqlite").write_text("payload", encoding="utf-8")

    result = run_backup(repo_copy, "core")

    assert result.returncode == 1
    assert "Falha ao copiar os dados" in result.stderr

    backup_dir = repo_copy / "backups" / "core-20240101-030405"
    assert backup_dir.is_dir()
    assert list(backup_dir.iterdir()) == []

    _assert_compose_restart_calls(compose_log, expected_core_apps)
    assert cp_log.read_text(encoding="utf-8").splitlines() == [
        "-a",
        f"{repo_copy}/data/core-root/app-core/.",
        f"{repo_copy}/backups/core-20240101-030405/",
    ]

    monkeypatch.setenv("PATH", original_path)
    for stub in fake_bin.iterdir():
        stub.unlink()
    fake_bin.rmdir()


def test_restart_failure_propagates_exit_code(
    repo_copy: Path,
    monkeypatch,
    compose_instances_data: ComposeInstancesData,
) -> None:
    expected_core_apps = compose_instances_data.instance_app_names.get("core", [])
    compose_log = _install_compose_stub(
        repo_copy,
        {"core": expected_core_apps},
        up_fail_instances={"core"},
    )
    _prepend_fake_bin(
        repo_copy,
        monkeypatch,
        (
            "date",
            "#!/usr/bin/env bash\nset -euo pipefail\nprintf '20240101-030405\\n'\n",
        ),
    )

    env_file = repo_copy / "env" / "local" / "core.env"
    env_file.write_text(
        env_file.read_text(encoding="utf-8") + "APP_DATA_DIR=data/core-root\n",
        encoding="utf-8",
    )

    data_mount = repo_copy / "data" / "core-root" / "app-core"
    data_mount.mkdir(parents=True)
    (data_mount / "db.sqlite").write_text("payload", encoding="utf-8")

    result = run_backup(repo_copy, "core")

    assert result.returncode == 1
    assert (
        "Falha ao religar as aplicações" in result.stderr
        and "instância 'core'" in result.stderr
    )
    assert "Processo finalizado com sucesso" not in result.stdout

    _assert_compose_restart_calls(compose_log, expected_core_apps)


def test_detected_apps_prioritize_known_order(
    repo_copy: Path,
    monkeypatch,
    compose_instances_data: ComposeInstancesData,
) -> None:
    expected_core_apps = compose_instances_data.instance_app_names.get("core", [])
    running_services = ["desconhecido"] + expected_core_apps
    compose_log = _install_compose_stub(
        repo_copy,
        {"core": running_services},
    )
    _prepend_fake_bin(
        repo_copy,
        monkeypatch,
        (
            "date",
            "#!/usr/bin/env bash\nset -euo pipefail\nprintf '20240101-030405\\n'\n",
        ),
    )

    env_file = repo_copy / "env" / "local" / "core.env"
    env_file.write_text(
        env_file.read_text(encoding="utf-8") + "APP_DATA_DIR=data/core-root\n",
        encoding="utf-8",
    )

    data_mount = repo_copy / "data" / "core-root" / "app-core"
    data_mount.mkdir(parents=True)

    result = run_backup(repo_copy, "core")

    assert result.returncode == 0, result.stderr
    line = next(
        (
            entry
            for entry in result.stdout.splitlines()
            if "Aplicações detectadas para religar:" in entry
        ),
        None,
    )
    assert line is not None, result.stdout
    _, _, tail = line.partition(":")
    apps = tail.strip().split()
    assert apps == [*expected_core_apps, "desconhecido"]

    _assert_compose_restart_calls(compose_log, [*expected_core_apps, "desconhecido"])


def test_no_restart_when_no_active_services(
    repo_copy: Path,
    monkeypatch,
    compose_instances_data: ComposeInstancesData,
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

    env_file = repo_copy / "env" / "local" / "core.env"
    env_file.write_text(
        env_file.read_text(encoding="utf-8") + "APP_DATA_DIR=data/core-root\n",
        encoding="utf-8",
    )

    data_mount = repo_copy / "data" / "core-root" / "app-core"
    data_mount.mkdir(parents=True)

    result = run_backup(repo_copy, "core")

    assert result.returncode == 0, result.stderr
    _assert_restart_apps(result.stdout, [])

    _assert_compose_restart_calls(compose_log, [])
