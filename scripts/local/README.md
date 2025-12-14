# Local script overrides

Repositories that must allow additional variables can create a
`scripts/local/check_env_sync.py` file and declare `IMPLICIT_ENV_VARS` with the
set of variables that should always be accepted by `scripts/check_env_sync.sh`.

```python
"""Local overrides for check_env_sync."""

from typing import Set

IMPLICIT_ENV_VARS: Set[str] = {
    # "MY_CUSTOM_VARIABLE",
}
```
