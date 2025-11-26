# Local script overrides

Repositories that need to allow additional variables can create a `scripts/local/check_env_sync.py` file and declare `IMPLICIT_ENV_VARS` with the set of variables automatically accepted.

```python
"""Local overrides for check_env_sync."""

from typing import Set

IMPLICIT_ENV_VARS: Set[str] = {
    # "MY_CUSTOM_VARIABLE",
}
```
