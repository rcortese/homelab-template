from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

import pytest

SCRIPT_RELATIVE = Path("scripts") / "check_db_integrity.sh"


@pytest.fixture
def compose_stub(tmp_path: Path) -> tuple[Path, Path]:
    log_path = tmp_path / "compose_stub.log"
    script_path = tmp_path / "compose_stub.sh"
    script_lines = [
        "#!/usr/bin/env bash",
        "set -euo pipefail",
        "",
        "log_file=${COMPOSE_STUB_LOG:?}",
        "{",
        "  printf '%q ' \"$@\"",
        "  printf '\\n'",
        "} >>\"$log_file\"",
        "",
        "skip_next=0",
        "cmd=\"\"",
        "for token in \"$@\"; do",
        "  if (( skip_next )); then",
        "    skip_next=0",
        "    continue",
        "  fi",
        "  case \"$token\" in",
        "    -f|--env-file|--project-directory|--profile|--ansi)",
        "      skip_next=1",
        "      continue",
        "      ;;",
        "    --*)",
        "      continue",
        "      ;;",
        "  esac",
        '  cmd="$token"',
        "  break",
        "done",
        "",
        "case \"$cmd\" in",
        "  ps)",
        '    if [[ -n "${COMPOSE_STUB_SERVICES:-}" ]]; then',
        '      printf "%s\\n" "$COMPOSE_STUB_SERVICES"',
        "    fi",
        "    ;;",
        "  pause|unpause)",
        "    ;;",
        "esac",
        "",
        'exit "${COMPOSE_STUB_EXIT_CODE:-0}"',
    ]
    script_path.write_text("\n".join(script_lines) + "\n", encoding="utf-8")
    script_path.chmod(0o755)
    return script_path, log_path


@pytest.fixture
def sqlite_stub(tmp_path: Path) -> tuple[Path, Path, Path]:
    config_path = tmp_path / "sqlite_stub_config.json"
    config_path.write_text("{}", encoding="utf-8")
    log_path = tmp_path / "sqlite_stub.log"
    script_path = tmp_path / "sqlite3"
    script_lines = [
        "#!/usr/bin/env python3",
        "import json",
        "import os",
        "import sys",
        "from pathlib import Path",
        "",
        "config_path = Path(os.environ['SQLITE3_STUB_CONFIG'])",
        "if config_path.exists():",
        "    config = json.loads(config_path.read_text(encoding='utf-8'))",
        "else:",
        "    config = {}",
        "",
        "log_path = Path(os.environ.get('SQLITE3_STUB_LOG', ''))",
        "if str(log_path):",
        "    with log_path.open('a', encoding='utf-8') as handle:",
        "        json.dump({'argv': sys.argv[1:]}, handle)",
        "        handle.write('\\n')",
        "",
        "args = sys.argv[1:]",
        "if not args:",
        "    sys.exit(0)",
        "",
        "default_cfg = config.get('__default__', {})",
        "",
        "def get_behavior(db: str) -> dict:",
        "    return config.get(db, default_cfg)",
        "",
        "",
        "def emit_streams(payload: dict) -> None:",
        "    stdout = payload.get('stdout', '')",
        "    stderr = payload.get('stderr', '')",
        "    if stdout:",
        "        sys.stdout.write(stdout)",
        "    if stderr:",
        "        sys.stderr.write(stderr)",
        "",
        "",
        "def handle_integrity(db: str, behavior: dict) -> int:",
        "    payload = behavior.get('integrity', {'stdout': 'ok', 'returncode': 0})",
        "    emit_streams(payload)",
        "    return int(payload.get('returncode', 0))",
        "",
        "",
        "def handle_recover(db: str, behavior: dict) -> int:",
        "    payload = behavior.get(",
        "        'recover',",
        "        {'stdout': 'BEGIN;\\nCOMMIT;\\n', 'returncode': 0},",
        "    )",
        "    emit_streams(payload)",
        "    return int(payload.get('returncode', 0))",
        "",
        "",
        "def handle_restore(db: str, behavior: dict) -> int:",
        "    payload = behavior.get('restore', {'returncode': 0})",
        "    data = sys.stdin.read()",
        "    Path(db).write_text(data, encoding='utf-8')",
        "    emit_streams(payload)",
        "    return int(payload.get('returncode', 0))",
        "",
        "",
        "db_path = args[0]",
        "behavior = get_behavior(db_path)",
        "",
        "if len(args) >= 2 and args[1] == 'PRAGMA integrity_check;':",
        "    sys.exit(handle_integrity(db_path, behavior))",
        "if len(args) >= 2 and args[1] == '.recover':",
        "    sys.exit(handle_recover(db_path, behavior))",
        "",
        "sys.exit(handle_restore(db_path, behavior))",
    ]
    script_path.write_text("\n".join(script_lines) + "\n", encoding="utf-8")
    script_path.chmod(0o755)
    return script_path, config_path, log_path


@pytest.fixture
def docker_stub(tmp_path: Path) -> tuple[Path, Path]:
    log_path = tmp_path / "docker_stub.log"
    script_path = tmp_path / "docker"
    script_lines = [
        "#!/usr/bin/env python3",
        "import json",
        "import os",
        "import subprocess",
        "import sys",
        "from pathlib import Path",
        "",
        "log_path = Path(os.environ['DOCKER_STUB_LOG'])",
        "with log_path.open('a', encoding='utf-8') as handle:",
        "    json.dump({'argv': sys.argv[1:]}, handle)",
        "    handle.write('\\n')",
        "",
        "args = sys.argv[1:]",
        "try:",
        "    idx = args.index('sqlite3')",
        "except ValueError:",
        "    sys.exit(0)",
        "",
        "container_args = args[idx + 1:]",
        "if not container_args:",
        "    sys.exit(0)",
        "",
        "stub_bin = os.environ['SQLITE3_CONTAINER_STUB_BIN']",
        "result = subprocess.run(",
        "    [stub_bin, *container_args],",
        "    stdin=sys.stdin,",
        "    stdout=sys.stdout,",
        "    stderr=sys.stderr,",
        "    check=False,",
        ")",
        "sys.exit(result.returncode)",
    ]
    script_path.write_text("\n".join(script_lines) + "\n", encoding="utf-8")
    script_path.chmod(0o755)
    return script_path, log_path


def _run_script(
    repo_copy: Path,
    compose_stub_path: Path,
    compose_log: Path,
    sqlite_stub_path: Path,
    sqlite_config: Path,
    sqlite_log: Path,
    *args: str,
    env: dict[str, str] | None = None,
    sqlite_mode: str | None = "binary",
) -> subprocess.CompletedProcess[str]:
    script_path = repo_copy / SCRIPT_RELATIVE
    result_env = os.environ.copy()
    result_env.update(
        {
            "DOCKER_COMPOSE_BIN": str(compose_stub_path),
            "COMPOSE_STUB_LOG": str(compose_log),
            "SQLITE3_BIN": str(sqlite_stub_path),
            "SQLITE3_STUB_CONFIG": str(sqlite_config),
            "SQLITE3_STUB_LOG": str(sqlite_log),
        }
    )
    if sqlite_mode is not None:
        result_env["SQLITE3_MODE"] = sqlite_mode
    if env:
        result_env.update(env)

    return subprocess.run(
        [str(script_path), *args],
        capture_output=True,
        text=True,
        cwd=repo_copy,
        env=result_env,
        check=False,
    )


def test_exits_when_no_databases(
    repo_copy: Path,
    compose_stub: tuple[Path, Path],
    sqlite_stub: tuple[Path, Path, Path],
) -> None:
    compose_stub_path, compose_log = compose_stub
    sqlite_stub_path, sqlite_config, sqlite_log = sqlite_stub

    (repo_copy / "data").mkdir()

    result = _run_script(
        repo_copy,
        compose_stub_path,
        compose_log,
        sqlite_stub_path,
        sqlite_config,
        sqlite_log,
        "core",
        env={"COMPOSE_STUB_SERVICES": ""},
    )

    assert result.returncode == 0, result.stderr
    assert "Nenhum arquivo .db encontrado" in result.stdout
    calls = compose_log.read_text(encoding="utf-8").splitlines()
    assert any(" ps " in call or call.rstrip().endswith(" ps") for call in calls)
    assert not any(" pause" in call for call in calls)


def test_pauses_and_checks_integrity(
    repo_copy: Path,
    compose_stub: tuple[Path, Path],
    sqlite_stub: tuple[Path, Path, Path],
) -> None:
    compose_stub_path, compose_log = compose_stub
    sqlite_stub_path, sqlite_config, sqlite_log = sqlite_stub

    data_dir = repo_copy / "data"
    data_dir.mkdir()
    db_path = data_dir / "app.db"
    db_path.write_text("dummy", encoding="utf-8")

    result = _run_script(
        repo_copy,
        compose_stub_path,
        compose_log,
        sqlite_stub_path,
        sqlite_config,
        sqlite_log,
        "core",
        env={"COMPOSE_STUB_SERVICES": "app\nworker"},
    )

    assert result.returncode == 0, result.stderr
    assert "Integridade OK" in result.stdout

    calls = compose_log.read_text(encoding="utf-8").splitlines()
    assert any(" pause " in call or call.rstrip().endswith(" pause") for call in calls)
    assert any(" unpause " in call or call.rstrip().endswith(" unpause") for call in calls)


def test_no_resume_skips_unpause(
    repo_copy: Path,
    compose_stub: tuple[Path, Path],
    sqlite_stub: tuple[Path, Path, Path],
) -> None:
    compose_stub_path, compose_log = compose_stub
    sqlite_stub_path, sqlite_config, sqlite_log = sqlite_stub

    data_dir = repo_copy / "data"
    data_dir.mkdir()
    db_path = data_dir / "app.db"
    db_path.write_text("dummy", encoding="utf-8")

    result = _run_script(
        repo_copy,
        compose_stub_path,
        compose_log,
        sqlite_stub_path,
        sqlite_config,
        sqlite_log,
        "core",
        "--no-resume",
        env={"COMPOSE_STUB_SERVICES": "app"},
    )

    assert result.returncode == 0, result.stderr
    assert "Integridade OK" in result.stdout

    calls = compose_log.read_text(encoding="utf-8").splitlines()
    assert any(" pause " in call or call.rstrip().endswith(" pause") for call in calls)
    assert not any(" unpause " in call or call.rstrip().endswith(" unpause") for call in calls)


def test_recovers_corrupted_database(
    repo_copy: Path,
    compose_stub: tuple[Path, Path],
    sqlite_stub: tuple[Path, Path, Path],
) -> None:
    compose_stub_path, compose_log = compose_stub
    sqlite_stub_path, sqlite_config, sqlite_log = sqlite_stub

    data_dir = repo_copy / "data"
    data_dir.mkdir()
    db_path = data_dir / "app.db"
    db_path.write_text("original", encoding="utf-8")

    config = {
        str(db_path): {
            "integrity": {"stdout": "malformed", "returncode": 0},
            "recover": {"stdout": "BEGIN;\nCREATE TABLE t(x);\nCOMMIT;\n", "returncode": 0},
        }
    }
    sqlite_config.write_text(json.dumps(config), encoding="utf-8")

    result = _run_script(
        repo_copy,
        compose_stub_path,
        compose_log,
        sqlite_stub_path,
        sqlite_config,
        sqlite_log,
        "core",
        env={"COMPOSE_STUB_SERVICES": "app"},
    )

    assert result.returncode == 0, result.stderr
    assert "Banco '" in result.stderr
    assert "recuperado" in result.stderr

    backups = list(db_path.parent.glob(f"{db_path.name}.*.bak"))
    assert backups, "Backup file should be created during recovery"
    assert compose_log.read_text(encoding="utf-8").count("unpause") == 1


def test_reports_failure_when_recovery_cannot_run(
    repo_copy: Path,
    compose_stub: tuple[Path, Path],
    sqlite_stub: tuple[Path, Path, Path],
) -> None:
    compose_stub_path, compose_log = compose_stub
    sqlite_stub_path, sqlite_config, sqlite_log = sqlite_stub

    data_dir = repo_copy / "data"
    data_dir.mkdir()
    db_path = data_dir / "broken.db"
    db_path.write_text("broken", encoding="utf-8")

    config = {
        str(db_path): {
            "integrity": {"stdout": "malformed", "returncode": 0},
            "recover": {
                "stdout": "",
                "stderr": "cannot recover",
                "returncode": 1,
            },
        }
    }
    sqlite_config.write_text(json.dumps(config), encoding="utf-8")

    result = _run_script(
        repo_copy,
        compose_stub_path,
        compose_log,
        sqlite_stub_path,
        sqlite_config,
        sqlite_log,
        "core",
        env={"COMPOSE_STUB_SERVICES": "app"},
    )

    assert result.returncode == 2
    assert "Falha ao recuperar" in result.stderr
    assert compose_log.read_text(encoding="utf-8").count("unpause") == 1


def test_runs_sqlite_via_container_when_requested(
    repo_copy: Path,
    compose_stub: tuple[Path, Path],
    sqlite_stub: tuple[Path, Path, Path],
    docker_stub: tuple[Path, Path],
) -> None:
    compose_stub_path, compose_log = compose_stub
    sqlite_stub_path, sqlite_config, sqlite_log = sqlite_stub
    docker_path, docker_log = docker_stub

    data_dir = repo_copy / "data"
    data_dir.mkdir()
    db_path = data_dir / "app.db"
    db_path.write_text("payload", encoding="utf-8")

    env = {
        "COMPOSE_STUB_SERVICES": "app",
        "PATH": f"{docker_path.parent}:{os.environ['PATH']}",
        "DOCKER_STUB_LOG": str(docker_log),
        "SQLITE3_CONTAINER_STUB_BIN": str(sqlite_stub_path),
    }

    result = _run_script(
        repo_copy,
        compose_stub_path,
        compose_log,
        sqlite_stub_path,
        sqlite_config,
        sqlite_log,
        "core",
        env=env,
        sqlite_mode="container",
    )

    assert result.returncode == 0, result.stderr
    docker_calls = [
        json.loads(line)["argv"]
        for line in docker_log.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    assert docker_calls, "docker stub should be invoked in container mode"
    assert any("sqlite3" in call for call in docker_calls)


def test_falls_back_to_binary_when_container_unavailable(
    repo_copy: Path,
    compose_stub: tuple[Path, Path],
    sqlite_stub: tuple[Path, Path, Path],
) -> None:
    compose_stub_path, compose_log = compose_stub
    sqlite_stub_path, sqlite_config, sqlite_log = sqlite_stub

    data_dir = repo_copy / "data"
    data_dir.mkdir()
    db_path = data_dir / "app.db"
    db_path.write_text("payload", encoding="utf-8")

    result = _run_script(
        repo_copy,
        compose_stub_path,
        compose_log,
        sqlite_stub_path,
        sqlite_config,
        sqlite_log,
        "core",
        env={
            "COMPOSE_STUB_SERVICES": "app",
            "SQLITE3_CONTAINER_RUNTIME": "nonexistent-docker",
        },
        sqlite_mode="container",
    )

    assert result.returncode == 0, result.stderr
    assert "Runtime 'nonexistent-docker' indisponível" in result.stderr
    stub_calls = [
        json.loads(line)["argv"]
        for line in sqlite_log.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    assert stub_calls, "fallback should execute sqlite stub directly"
