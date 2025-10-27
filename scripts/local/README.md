# Local script overrides

Repositórios que precisam permitir variáveis adicionais podem criar um arquivo
`scripts/local/check_env_sync.py` e declarar `IMPLICIT_ENV_VARS` com o conjunto
de variáveis aceitas automaticamente.

```python
"""Overrides locais para check_env_sync."""

from typing import Set

IMPLICIT_ENV_VARS: Set[str] = {
    # "MINHA_VARIAVEL_CUSTOMIZADA",
}
```
