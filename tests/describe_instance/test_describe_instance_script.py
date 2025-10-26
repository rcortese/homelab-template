from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

SCRIPT_RELATIVE = Path("scripts") / "describe_instance.sh"


def _build_compose_stub(tmp_path: Path, config_payload: dict[str, object]) -> tuple[Path, Path]:
    script_path = tmp_path / "compose_stub.py"
    log_path = tmp_path / "compose_stub.log"
    config_path = tmp_path / "config.json"
    config_path.write_text(json.dumps(config_payload), encoding="utf-8")

    script_lines = [
        "#!/usr/bin/env python3",
        "import json",
        "import os",
        "import pathlib",
        "import sys",
        "",
        "log_path = pathlib.Path(os.environ['DESCRIBE_INSTANCE_COMPOSE_LOG'])",
        "with log_path.open('a', encoding='utf-8') as handle:",
        "    json.dump({'argv': sys.argv[1:]}, handle)",
        "    handle.write('\\n')",
        "",
        "args = sys.argv[1:]",
        "filtered = []",
        "i = 0",
        "while i < len(args):",
        "    token = args[i]",
        "    if token in {'-f', '--env-file'} and i + 1 < len(args):",
        "        i += 2",
        "        continue",
        "    filtered.append(token)",
        "    i += 1",
        "",
        "payload_path = pathlib.Path(os.environ['DESCRIBE_INSTANCE_CONFIG_JSON'])",
        "payload = payload_path.read_text(encoding='utf-8')",
        "",
        "if filtered[:3] == ['config', '--format', 'json']:",
        "    print(payload)",
        "    sys.exit(0)",
        "if filtered[:1] == ['config']:",
        "    print(payload)",
        "    sys.exit(0)",
        "",
        "sys.exit(0)",
    ]

    script_path.write_text("\n".join(script_lines) + "\n", encoding="utf-8")
    script_path.chmod(0o755)
    return script_path, log_path


def _run_script(repo_copy: Path, *args: str, env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    script_path = repo_copy / SCRIPT_RELATIVE
    result = subprocess.run(
        [str(script_path), *args],
        capture_output=True,
        text=True,
        cwd=repo_copy,
        env=env,
        check=False,
    )
    return result


def test_table_summary_highlights_overlays(repo_copy: Path, tmp_path: Path) -> None:
    compose_payload = {
        "services": {
            "app": {
                "ports": [
                    {"target": 80, "published": 8080, "protocol": "tcp"},
                    {
                        "target": 443,
                        "published": 8443,
                        "protocol": "tcp",
                        "host_ip": "127.0.0.1",
                    },
                ],
                "volumes": [
                    {
                        "type": "bind",
                        "source": "/srv/app/data",
                        "target": "/data/app",
                        "read_only": False,
                    },
                    "app-data:/var/lib/app",
                ],
            },
            "monitoring": {
                "ports": [],
                "volumes": [
                    {
                        "type": "volume",
                        "source": "monitoring-config",
                        "target": "/etc/monitoring",
                    }
                ],
            },
        }
    }

    stub_path, log_path = _build_compose_stub(tmp_path, compose_payload)

    env = os.environ.copy()
    env.update(
        {
            "DOCKER_COMPOSE_BIN": str(stub_path),
            "DESCRIBE_INSTANCE_CONFIG_JSON": str((tmp_path / "config.json").resolve()),
            "DESCRIBE_INSTANCE_COMPOSE_LOG": str(log_path),
            "COMPOSE_EXTRA_FILES": "compose/overlays/metrics.yml compose/overlays/logging.yml",
        }
    )

    result = _run_script(repo_copy, "core", env=env)
    assert result.returncode == 0, result.stderr

    stdout = result.stdout
    assert "Instância: core" in stdout
    assert "compose/base.yml" in stdout
    assert "compose/apps/app/base.yml" in stdout
    assert "compose/apps/monitoring/base.yml" in stdout
    assert "compose/overlays/metrics.yml (overlay extra)" in stdout
    assert "Overlays extras aplicados:" in stdout
    assert "compose/overlays/logging.yml" in stdout
    assert "Portas publicadas:" in stdout
    assert "8080 -> 80/tcp" in stdout
    assert "127.0.0.1:8443 -> 443/tcp" in stdout
    assert "Volumes montados:" in stdout
    assert "/srv/app/data -> /data/app (read_only=False, type=bind)" in stdout
    assert "monitoring-config -> /etc/monitoring (type=volume)" in stdout

    log_lines = [line for line in log_path.read_text(encoding="utf-8").splitlines() if line.strip()]
    assert log_lines, "esperado ao menos uma chamada ao stub do docker compose"
    parsed = [json.loads(line)["argv"] for line in log_lines]
    assert any(entry[-3:] == ["config", "--format", "json"] for entry in parsed)


def test_json_summary_structure(repo_copy: Path, tmp_path: Path) -> None:
    compose_payload = {
        "services": {
            "app": {
                "ports": [
                    {"target": 80, "published": 8080, "protocol": "tcp"},
                ],
                "volumes": [
                    {
                        "type": "bind",
                        "source": "/srv/app/data",
                        "target": "/data/app",
                    }
                ],
            },
            "monitoring": {
                "ports": [],
                "volumes": [],
            },
        }
    }

    stub_path, log_path = _build_compose_stub(tmp_path, compose_payload)

    env = os.environ.copy()
    env.update(
        {
            "DOCKER_COMPOSE_BIN": str(stub_path),
            "DESCRIBE_INSTANCE_CONFIG_JSON": str((tmp_path / "config.json").resolve()),
            "DESCRIBE_INSTANCE_COMPOSE_LOG": str(log_path),
            "COMPOSE_EXTRA_FILES": "compose/overlays/metrics.yml",
        }
    )

    result = _run_script(repo_copy, "core", "--format", "json", env=env)
    assert result.returncode == 0, result.stderr

    payload = json.loads(result.stdout)
    assert payload["instance"] == "core"

    compose_files = [entry["path"] for entry in payload["compose_files"]]
    assert compose_files == [
        "compose/base.yml",
        "compose/apps/app/base.yml",
        "compose/apps/app/core.yml",
        "compose/apps/monitoring/base.yml",
        "compose/apps/monitoring/core.yml",
        "compose/overlays/metrics.yml",
    ]

    extra_flags = [entry["is_extra"] for entry in payload["compose_files"]]
    assert extra_flags[-1] is True
    assert any(flag is False for flag in extra_flags[:-1])

    assert payload["extra_overlays"] == ["compose/overlays/metrics.yml"]

    services = payload["services"]
    assert [service["name"] for service in services] == ["app", "monitoring"]

    app_service = services[0]
    assert app_service["ports"] == ["8080 -> 80/tcp"]
    assert app_service["volumes"] == ["/srv/app/data -> /data/app (type=bind)"]

    log_lines = [line for line in log_path.read_text(encoding="utf-8").splitlines() if line.strip()]
    assert log_lines, "esperado ao menos uma chamada ao stub do docker compose"
    parsed = [json.loads(line)["argv"] for line in log_lines]
    assert any(entry[-3:] == ["config", "--format", "json"] for entry in parsed)

    monitoring_service = services[1]
    assert monitoring_service["ports"] == []
    assert monitoring_service["volumes"] == []
