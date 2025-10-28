from __future__ import annotations

import json
import os
import shutil
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
    use_sqlite_stub: bool = True,
) -> subprocess.CompletedProcess[str]:
    script_path = repo_copy / SCRIPT_RELATIVE
    result_env = os.environ.copy()
    result_env.update(
        {
            "DOCKER_COMPOSE_BIN": str(compose_stub_path),
            "COMPOSE_STUB_LOG": str(compose_log),
        }
    )
    if use_sqlite_stub:
        result_env.update(
            {
                "SQLITE3_BIN": str(sqlite_stub_path),
                "SQLITE3_STUB_CONFIG": str(sqlite_config),
                "SQLITE3_STUB_LOG": str(sqlite_log),
            }
        )
    else:
        result_env.pop("SQLITE3_BIN", None)
        result_env.pop("SQLITE3_STUB_CONFIG", None)
        result_env.pop("SQLITE3_STUB_LOG", None)
        stub_dir = str(sqlite_stub_path.parent)
        path_value = result_env.get("PATH", "")
        if path_value:
            cleaned_path = os.pathsep.join(
                entry for entry in path_value.split(os.pathsep) if entry != stub_dir
            )
            result_env["PATH"] = cleaned_path
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


def test_json_output_contains_results(
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
        "--format",
        "json",
        env={"COMPOSE_STUB_SERVICES": "app"},
    )

    assert result.returncode == 0, result.stderr
    payload = json.loads(result.stdout)
    assert payload["format"] == "json"
    assert payload["overall_status"] == 0
    assert payload["alerts"] == []
    databases = {entry["path"]: entry for entry in payload["databases"]}
    assert str(db_path) in databases
    entry = databases[str(db_path)]
    assert entry["status"] == "ok"
    assert entry["message"] == "Integridade OK"
    assert entry["action"] == "Nenhuma ação necessária"


def test_handles_compose_ps_failure(
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
        env={
            "COMPOSE_STUB_EXIT_CODE": "42",
            "COMPOSE_STUB_LOG": str(compose_log),
        },
    )

    assert result.returncode == 0, result.stderr
    assert "[!] Não foi possível listar serviços ativos da instância" in result.stderr
    assert "Integridade OK" in result.stdout

    compose_output = compose_log.read_text(encoding="utf-8")
    assert "pause" not in compose_output
    assert "unpause" not in compose_output


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


def test_json_output_reports_corrupted_database_alerts(
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
            "recover": {"stderr": "simulated recover failure", "returncode": 1},
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
        "--format",
        "json",
        env={"COMPOSE_STUB_SERVICES": "app"},
    )

    assert result.returncode == 2
    assert "Falha ao recuperar" in result.stderr

    payload = json.loads(result.stdout)
    assert payload["format"] == "json"
    assert payload["overall_status"] == 2

    expected_alerts = [
        f"Falha de integridade: malformed em {db_path}",
        f"Banco '{db_path}' permanece corrompido: sqlite3 .recover falhou: simulated recover failure",
    ]
    assert payload["alerts"] == expected_alerts

    databases = {entry["path"]: entry for entry in payload["databases"]}
    assert str(db_path) in databases
    entry = databases[str(db_path)]
    assert entry["status"] == "failed"
    assert entry["message"] == "Falha de integridade: malformed"
    assert (
        entry["action"]
        == "Recuperação automática falhou: sqlite3 .recover falhou: simulated recover failure"
    )


def test_writes_text_report_to_output_file(
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

    output_path = repo_copy / "report.txt"

    result = _run_script(
        repo_copy,
        compose_stub_path,
        compose_log,
        sqlite_stub_path,
        sqlite_config,
        sqlite_log,
        "core",
        "--output",
        str(output_path),
        env={"COMPOSE_STUB_SERVICES": "app"},
    )

    assert result.returncode == 0, result.stderr
    report_content = output_path.read_text(encoding="utf-8")
    assert "Resumo da verificação de bancos SQLite" in report_content
    assert f"Banco: {db_path}" in report_content
    assert "status: ok" in report_content
    assert "mensagem: Integridade OK" in report_content
    assert "acao: Nenhuma ação necessária" in report_content


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


def test_binary_mode_requires_sqlite_binary(
    repo_copy: Path,
    compose_stub: tuple[Path, Path],
    sqlite_stub: tuple[Path, Path, Path],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    compose_stub_path, compose_log = compose_stub
    sqlite_stub_path, sqlite_config, sqlite_log = sqlite_stub

    (repo_copy / "data").mkdir()

    original_path = os.environ.get("PATH")
    cleaned_path = os.pathsep.join(
        entry
        for entry in (original_path or "").split(os.pathsep)
        if entry and entry != str(sqlite_stub_path.parent)
    )
    effective_path = cleaned_path or (original_path or os.defpath)
    monkeypatch.setenv("PATH", effective_path)
    try:
        result = _run_script(
            repo_copy,
            compose_stub_path,
            compose_log,
            sqlite_stub_path,
            sqlite_config,
            sqlite_log,
            "core",
            sqlite_mode="binary",
            use_sqlite_stub=False,
            env={"SQLITE3_BIN": "/nonexistent/sqlite3"},
        )
    finally:
        if original_path is None:
            monkeypatch.delenv("PATH", raising=False)
        else:
            monkeypatch.setenv("PATH", original_path)

    assert result.returncode == 127
    assert "Erro: sqlite3 não encontrado (binário:" in result.stderr


def test_container_mode_errors_when_runtime_and_binary_missing(
    repo_copy: Path,
    compose_stub: tuple[Path, Path],
    sqlite_stub: tuple[Path, Path, Path],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    compose_stub_path, compose_log = compose_stub
    sqlite_stub_path, sqlite_config, sqlite_log = sqlite_stub

    (repo_copy / "data").mkdir()

    original_path = os.environ.get("PATH")
    cleaned_path = os.pathsep.join(
        entry
        for entry in (original_path or "").split(os.pathsep)
        if entry and entry != str(sqlite_stub_path.parent)
    )
    effective_path = cleaned_path or (original_path or os.defpath)
    monkeypatch.setenv("PATH", effective_path)
    try:
        result = _run_script(
            repo_copy,
            compose_stub_path,
            compose_log,
            sqlite_stub_path,
            sqlite_config,
            sqlite_log,
            "core",
            env={
                "SQLITE3_CONTAINER_RUNTIME": "fake-runtime",
                "SQLITE3_BIN": "/nonexistent/sqlite3",
            },
            sqlite_mode="container",
            use_sqlite_stub=False,
        )
    finally:
        if original_path is None:
            monkeypatch.delenv("PATH", raising=False)
        else:
            monkeypatch.setenv("PATH", original_path)

    assert result.returncode == 127
    assert (
        "Erro: runtime 'fake-runtime' indisponível e sqlite3 (binário:" in result.stderr
    )


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


def test_accepts_custom_data_dir(
    repo_copy: Path,
    compose_stub: tuple[Path, Path],
    sqlite_stub: tuple[Path, Path, Path],
) -> None:
    compose_stub_path, compose_log = compose_stub
    sqlite_stub_path, sqlite_config, sqlite_log = sqlite_stub

    data_dir = repo_copy / "alt-data"
    data_dir.mkdir()
    db_path = data_dir / "custom.db"
    db_path.write_text("dummy", encoding="utf-8")

    result: subprocess.CompletedProcess[str]
    try:
        result = _run_script(
            repo_copy,
            compose_stub_path,
            compose_log,
            sqlite_stub_path,
            sqlite_config,
            sqlite_log,
            "core",
            "--data-dir",
            "alt-data",
            env={"COMPOSE_STUB_SERVICES": "app"},
        )
    finally:
        shutil.rmtree(data_dir, ignore_errors=True)

    assert result.returncode == 0, result.stderr
    assert str(db_path) in result.stdout


def test_errors_when_data_dir_env_missing(
    repo_copy: Path,
    compose_stub: tuple[Path, Path],
    sqlite_stub: tuple[Path, Path, Path],
) -> None:
    compose_stub_path, compose_log = compose_stub
    sqlite_stub_path, sqlite_config, sqlite_log = sqlite_stub

    result = _run_script(
        repo_copy,
        compose_stub_path,
        compose_log,
        sqlite_stub_path,
        sqlite_config,
        sqlite_log,
        "core",
        env={"DATA_DIR": "missing-dir"},
    )

    assert result.returncode == 1
    assert "Erro: diretório de dados não encontrado" in result.stderr
