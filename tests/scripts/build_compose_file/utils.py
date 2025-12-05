from __future__ import annotations

import json
import os
import subprocess
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
SCRIPT_PATH = REPO_ROOT / "scripts" / "build_compose_file.sh"


@dataclass
class ComposeConfigStub:
    path: Path
    log_path: Path
    output_content: str

    @property
    def base_env(self) -> dict[str, str]:
        return {
            "COMPOSE_STUB_LOG": str(self.log_path),
            "COMPOSE_STUB_OUTPUT_CONTENT": self.output_content,
        }

    def read_calls(self) -> list[list[str]]:
        if not self.log_path.exists():
            return []

        entries: list[list[str]] = []
        for line in self.log_path.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            record = json.loads(line)
            args = record.get("args")
            if isinstance(args, list):
                entries.append([str(item) for item in args])
            else:
                entries.append([])
        return entries


def create_compose_config_stub(tmp_path: Path, *, output_content: str = "version: '3.9'\nservices: {}\n") -> ComposeConfigStub:
    log_path = tmp_path / "compose_config_stub_calls.jsonl"
    stub_path = tmp_path / "compose-config-stub"

    stub_path.write_text(
        f"""#!/usr/bin/env python3
import json
import os
import pathlib
import sys

log_path = pathlib.Path(os.environ['COMPOSE_STUB_LOG'])
output_content = os.environ.get('COMPOSE_STUB_OUTPUT_CONTENT', {output_content!r})
args = sys.argv[1:]

with log_path.open('a', encoding='utf-8') as handle:
    json.dump({{'args': args}}, handle)
    handle.write('\\n')

if '--output' in args:
    output_index = args.index('--output') + 1
    if output_index < len(args):
        target = pathlib.Path(args[output_index])
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(output_content, encoding='utf-8')

sys.exit(0)
""",
        encoding="utf-8",
    )
    stub_path.chmod(0o755)

    return ComposeConfigStub(path=stub_path, log_path=log_path, output_content=output_content)


def run_build_compose_file(
    *,
    args: list[str] | None = None,
    env: dict[str, str] | None = None,
    cwd: Path | None = None,
    script_path: Path | None = None,
) -> subprocess.CompletedProcess[str]:
    command = [str(script_path or SCRIPT_PATH)]
    if args:
        command.extend(args)

    return subprocess.run(
        command,
        capture_output=True,
        text=True,
        check=False,
        cwd=cwd or REPO_ROOT,
        env={**os.environ, **(env or {})},
    )
