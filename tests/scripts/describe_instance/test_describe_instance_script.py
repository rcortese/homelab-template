from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

from tests.helpers.compose_instances import ComposeInstancesData

SCRIPT_RELATIVE = Path("scripts") / "describe_instance.sh"


def _format_port(port: object) -> str:
    if isinstance(port, str):
        return port
    if not isinstance(port, dict):
        return str(port)

    target = port.get("target")
    published = port.get("published")
    protocol = port.get("protocol") or "tcp"
    mode = port.get("mode")
    host_ip = port.get("host_ip")

    left_parts: list[str] = []
    if host_ip:
        left_parts.append(str(host_ip))
    if published is not None:
        left_parts.append(str(published))

    left = ":".join(left_parts) if left_parts else ""
    right = str(target) if target is not None else ""

    pieces: list[str] = []
    if left:
        pieces.append(left)
    if right:
        if pieces:
            pieces.append("->")
        pieces.append(right)

    result = " ".join(pieces) if pieces else (right or left or "")
    if result:
        result = f"{result}/{protocol}"
    else:
        result = f"{target}/{protocol}" if target is not None else f"{protocol}"

    if mode and mode not in {"ingress"}:
        result = f"{result} ({mode})"

    return result


def _format_volume(volume: object) -> str:
    if isinstance(volume, str):
        return volume
    if not isinstance(volume, dict):
        return str(volume)

    source = volume.get("source")
    target = volume.get("target")

    if source and target:
        base = f"{source} -> {target}"
    elif target:
        base = str(target)
    elif source:
        base = str(source)
    else:
        base = ""

    details = {k: v for k, v in volume.items() if k not in {"source", "target"}}
    if not details:
        return base or json.dumps(volume, ensure_ascii=False, sort_keys=True)

    detail_items = []
    for key in sorted(details):
        value = details[key]
        if isinstance(value, dict):
            detail_items.append(
                f"{key}={json.dumps(value, ensure_ascii=False, sort_keys=True)}"
            )
        else:
            detail_items.append(f"{key}={value}")

    detail_str = ", ".join(detail_items)
    if base:
        return f"{base} ({detail_str})"
    return detail_str


def _build_compose_stub(
    tmp_path: Path, config_payload: dict[str, object]
) -> tuple[Path, Path]:
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
        "exit_override = os.environ.get('DESCRIBE_INSTANCE_COMPOSE_EXIT')",
        "stderr_message = os.environ.get('DESCRIBE_INSTANCE_COMPOSE_STDERR', '')",
        "if filtered[:3] == ['config', '--format', 'json'] and exit_override:",
        "    try:",
        "        exit_code = int(exit_override)",
        "    except ValueError:",
        "        exit_code = 1",
        "    if stderr_message:",
        "        print(stderr_message, file=sys.stderr)",
        "    sys.exit(exit_code)",
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


def _find_config_json_call(entries: list[list[str]]) -> list[str]:
    for entry in entries:
        if len(entry) >= 3 and entry[-3:] == ["config", "--format", "json"]:
            return entry
    raise AssertionError("esperado chamada 'docker compose config --format json'")


def _extract_flag_arguments(args: list[str], flag: str) -> list[str]:
    values: list[str] = []
    index = 0
    while index < len(args):
        token = args[index]
        if token == flag:
            assert index + 1 < len(args), f"flag {flag} sem valor em {args!r}"
            values.append(args[index + 1])
            index += 2
            continue
        index += 1
    return values


def test_format_flag_requires_value(repo_copy: Path, tmp_path: Path) -> None:
    stub_path, log_path = _build_compose_stub(tmp_path, {"services": {}})

    env = os.environ.copy()
    env.update(
        {
            "DOCKER_COMPOSE_BIN": str(stub_path),
            "DESCRIBE_INSTANCE_CONFIG_JSON": str((tmp_path / "config.json").resolve()),
            "DESCRIBE_INSTANCE_COMPOSE_LOG": str(log_path),
        }
    )

    result = _run_script(repo_copy, "--format", env=env)

    assert result.returncode == 1
    assert "Error: --format requires a value" in result.stderr


def test_invalid_format_value_errors(repo_copy: Path, tmp_path: Path) -> None:
    stub_path, log_path = _build_compose_stub(tmp_path, {"services": {}})

    env = os.environ.copy()
    env.update(
        {
            "DOCKER_COMPOSE_BIN": str(stub_path),
            "DESCRIBE_INSTANCE_CONFIG_JSON": str((tmp_path / "config.json").resolve()),
            "DESCRIBE_INSTANCE_COMPOSE_LOG": str(log_path),
        }
    )

    result = _run_script(repo_copy, "--format", "yaml", "core", env=env)

    assert result.returncode == 1
    assert "Error: invalid format 'yaml'. Use 'table' or 'json'." in result.stderr


def test_list_flag_cannot_receive_instance(repo_copy: Path, tmp_path: Path) -> None:
    stub_path, log_path = _build_compose_stub(tmp_path, {"services": {}})

    env = os.environ.copy()
    env.update(
        {
            "DOCKER_COMPOSE_BIN": str(stub_path),
            "DESCRIBE_INSTANCE_CONFIG_JSON": str((tmp_path / "config.json").resolve()),
            "DESCRIBE_INSTANCE_COMPOSE_LOG": str(log_path),
        }
    )

    result = _run_script(repo_copy, "--list", "core", env=env)

    assert result.returncode == 1
    assert "Error: --list cannot be combined with an instance name." in result.stderr


def test_instance_name_is_required(repo_copy: Path, tmp_path: Path) -> None:
    stub_path, log_path = _build_compose_stub(tmp_path, {"services": {}})

    env = os.environ.copy()
    env.update(
        {
            "DOCKER_COMPOSE_BIN": str(stub_path),
            "DESCRIBE_INSTANCE_CONFIG_JSON": str((tmp_path / "config.json").resolve()),
            "DESCRIBE_INSTANCE_COMPOSE_LOG": str(log_path),
        }
    )

    result = _run_script(repo_copy, env=env)

    assert result.returncode == 1
    assert "Error: provide the instance name." in result.stderr
    assert "Usage: scripts/describe_instance.sh" in result.stderr


def test_list_flag_prints_available_instances(
    repo_copy: Path, compose_instances_data: ComposeInstancesData
) -> None:
    env = os.environ.copy()

    result = _run_script(repo_copy, "--list", env=env)

    assert result.returncode == 0, result.stderr

    lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    assert lines, "expected output content"
    assert lines[0] == "Available instances:"

    bullets = [line[2:].strip() for line in lines[1:] if line.startswith("• ")]
    assert bullets == compose_instances_data.instance_names


def test_table_summary_highlights_extra_files(
    repo_copy: Path,
    tmp_path: Path,
    compose_instances_data: ComposeInstancesData,
) -> None:
    service_with_ports = "primary"
    service_with_volume = "metrics"
    service_stateless = "batch"
    service_extra = "analytics"
    service_extra_only = "delta"

    compose_payload = {
        "services": {
            service_with_ports: {
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
                        "source": "/srv/primary/data",
                        "target": "/data/primary",
                        "read_only": False,
                    },
                    "primary-data:/var/lib/primary",
                ],
            },
            service_with_volume: {
                "ports": [],
                "volumes": [
                    {
                        "type": "volume",
                        "source": "metrics-config",
                        "target": "/etc/metrics",
                    }
                ],
            },
            service_stateless: {
                "ports": [],
                "volumes": [],
            },
            service_extra: {
                "ports": [],
                "volumes": [],
            },
            service_extra_only: {
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
        }
    )

    result = _run_script(repo_copy, "core", env=env)
    assert result.returncode == 0, result.stderr

    stdout = result.stdout
    assert "Instance: core" in stdout
    assert "docker-compose.yml" in stdout
    assert "Published ports:" in stdout
    for port in compose_payload["services"][service_with_ports]["ports"]:
        formatted = _format_port(port)
        assert formatted in stdout
    assert "Mounted volumes:" in stdout
    primary_volumes = compose_payload["services"][service_with_ports]["volumes"]
    for volume in primary_volumes:
        formatted = _format_volume(volume)
        assert formatted in stdout
    metrics_volumes = compose_payload["services"][service_with_volume]["volumes"]
    for volume in metrics_volumes:
        formatted = _format_volume(volume)
        assert formatted in stdout

    log_lines = [line for line in log_path.read_text(encoding="utf-8").splitlines() if line.strip()]
    assert log_lines, "expected at least one call to the docker compose stub"
    parsed = [json.loads(line)["argv"] for line in log_lines]
    config_call = _find_config_json_call(parsed)

    compose_args = _extract_flag_arguments(config_call, "-f")
    expected_compose_files = [repo_copy / "docker-compose.yml"]
    assert compose_args == [str(path.resolve(strict=False)) for path in expected_compose_files]

    env_files = _extract_flag_arguments(config_call, "--env-file")
    assert env_files == []


def test_json_summary_structure(
    repo_copy: Path, tmp_path: Path, compose_instances_data: ComposeInstancesData
) -> None:
    service_with_ports = "primary"
    service_with_volume = "metrics"
    service_stateless = "batch"
    service_extra = "analytics"
    service_extra_only = "delta"

    compose_payload = {
        "services": {
            service_with_ports: {
                "ports": [
                    {"target": 80, "published": 8080, "protocol": "tcp"},
                ],
                "volumes": [
                    {
                        "type": "bind",
                        "source": "/srv/primary/data",
                        "target": "/data/primary",
                    }
                ],
            },
            service_with_volume: {
                "ports": [],
                "volumes": [
                    {
                        "type": "volume",
                        "source": "metrics-config",
                        "target": "/etc/metrics",
                    }
                ],
            },
            service_stateless: {
                "ports": [],
                "volumes": [],
            },
            service_extra: {
                "ports": [],
                "volumes": [],
            },
            service_extra_only: {
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
        }
    )

    result = _run_script(repo_copy, "core", "--format", "json", env=env)
    assert result.returncode == 0, result.stderr

    payload = json.loads(result.stdout)
    assert payload["instance"] == "core"

    compose_files = [entry["path"] for entry in payload["compose_files"]]
    assert compose_files == ["docker-compose.yml"]
    assert payload["extra_files"] == []

    services = payload["services"]
    names = [service["name"] for service in services]
    assert sorted(names) == sorted(compose_payload["services"].keys())

    service_lookup = {service["name"]: service for service in services}
    primary_service = service_lookup[service_with_ports]
    assert primary_service["ports"] == [
        _format_port(port)
        for port in compose_payload["services"][service_with_ports]["ports"]
    ]
    assert primary_service["volumes"] == [
        _format_volume(volume)
        for volume in compose_payload["services"][service_with_ports]["volumes"]
    ]

    log_lines = [line for line in log_path.read_text(encoding="utf-8").splitlines() if line.strip()]
    assert log_lines, "expected at least one call to the docker compose stub"
    parsed = [json.loads(line)["argv"] for line in log_lines]
    config_call = _find_config_json_call(parsed)

    compose_args = _extract_flag_arguments(config_call, "-f")
    expected_compose_files = [repo_copy / "docker-compose.yml"]
    assert compose_args == [str(path.resolve(strict=False)) for path in expected_compose_files]

    env_files = _extract_flag_arguments(config_call, "--env-file")
    assert env_files == []

    for name, definition in compose_payload["services"].items():
        current = service_lookup[name]
        assert current["ports"] == [_format_port(port) for port in definition.get("ports", [])]
        assert current["volumes"] == [
            _format_volume(volume) for volume in definition.get("volumes", [])
        ]


def test_compose_config_failure_is_propagated(repo_copy: Path, tmp_path: Path) -> None:
    compose_payload = {"services": {"sample": {"ports": [], "volumes": []}}}

    stub_path, log_path = _build_compose_stub(tmp_path, compose_payload)

    env = os.environ.copy()
    env.update(
        {
            "DOCKER_COMPOSE_BIN": str(stub_path),
            "DESCRIBE_INSTANCE_CONFIG_JSON": str((tmp_path / "config.json").resolve()),
            "DESCRIBE_INSTANCE_COMPOSE_LOG": str(log_path),
            "DESCRIBE_INSTANCE_COMPOSE_EXIT": "42",
            "DESCRIBE_INSTANCE_COMPOSE_STDERR": "docker compose config failed",
        }
    )

    result = _run_script(repo_copy, "core", env=env)

    assert result.returncode == 42
    assert "Error: failed to run docker compose config." in result.stderr
    assert "docker compose config failed" in result.stderr
    assert result.stdout == ""

    log_lines = [line for line in log_path.read_text(encoding="utf-8").splitlines() if line.strip()]
    assert log_lines, "expected at least one call to the docker compose stub"
