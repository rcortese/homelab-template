"""Environment template helpers for env sync checks."""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Set


@dataclass
class EnvTemplateData:
    defined: Set[str]
    documented: Set[str]

    @property
    def available(self) -> Set[str]:
        return self.defined | self.documented


def load_env_variables(path: Path) -> EnvTemplateData:
    lines = path.read_text(encoding="utf-8").splitlines()
    defined: Set[str] = set()
    documented: Set[str] = set()
    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue

        is_comment = stripped.startswith("#")
        candidate = stripped[1:] if is_comment else stripped
        candidate = candidate.strip()

        if candidate.startswith("export "):
            candidate = candidate[len("export ") :].lstrip()

        if "=" not in candidate:
            continue

        name, _ = candidate.split("=", 1)
        name = name.strip()
        if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", name):
            continue

        if is_comment:
            documented.add(name)
        else:
            defined.add(name)
    return EnvTemplateData(defined=defined, documented=documented)
