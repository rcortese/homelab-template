import sys
import textwrap
import types
from pathlib import Path

yaml_stub = types.SimpleNamespace(
    safe_load_all=lambda _content: [],
    YAMLError=Exception,
)
sys.modules.setdefault("yaml", yaml_stub)

from scripts.lib.check_env_sync.env_templates import load_env_variables


def test_load_env_variables_classifies_defined_and_documented_entries(tmp_path: Path) -> None:
    env_content = textwrap.dedent(
        """
        FOO=value
        export BAR=other
        # BAZ=Documented variable
        # export QUX=Documented exported variable
        INVALID-NAME=value
        1INVALID=value
        export _VALID=1
        """
    ).strip()

    env_path = tmp_path / ".env"
    env_path.write_text(env_content, encoding="utf-8")

    data = load_env_variables(env_path)

    assert data.defined == {"FOO", "BAR", "_VALID"}
    assert data.documented == {"BAZ", "QUX"}
    assert "INVALID-NAME" not in data.defined
    assert "1INVALID" not in data.defined
    assert "INVALID-NAME" not in data.documented
    assert "1INVALID" not in data.documented
