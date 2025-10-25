# Guia de combinações do Docker Compose

> Parte do [índice da documentação](./README.md). Leia a [Visão Geral](./OVERVIEW.md) para entender os papéis das instâncias e alinhe checklists com os runbooks da [core](./core.md) e da [media](./media.md).

Este guia documenta como montar o manifesto do Docker Compose usando apenas os
arquivos base e os overrides por instância. Siga estas instruções antes de
executar `docker compose` ou os scripts em `scripts/*.sh`.

## Estrutura dos manifests

| Tipo de arquivo | Localização | Papel |
| --------------- | ----------- | ----- |
| **Base** | `compose/base.yml` | Define imagem padrão da aplicação, volumes compartilhados (`../data/${SERVICE_NAME:-app}`, `../backups`), variáveis comuns (`TZ`, `APP_SECRET`, `APP_RETENTION_HOURS`) e política de restart. É carregado em **todas** as combinações. |
| **Overrides de instância** | `compose/<instância>.yml` | Ajustam o container para cada ambiente (nome, porta exposta, URLs públicas e variáveis específicas como `MEDIA_ROOT`). Devem ser combinados exatamente com uma instância (ex.: `core` ou `media`). |

## Exemplos de comando

### Core

```bash
docker compose \
  --env-file env/local/core.env \
  -f compose/base.yml \
  -f compose/core.yml \
  up -d
```

### Media (com volume de mídia)

```bash
docker compose \
  --env-file env/local/media.env \
  -f compose/base.yml \
  -f compose/media.yml \
  up -d
```

### Combinação ad-hoc com `COMPOSE_FILES`

```bash
export COMPOSE_FILES="compose/base.yml compose/media.yml"
docker compose \
  --env-file env/local/media.env \
  $(for file in $COMPOSE_FILES; do printf ' -f %s' "$file"; done) \
  up -d
```

## Boas práticas

- Sempre carregue `compose/base.yml` em primeiro lugar.
- Combine o override `compose/<instância>.yml` correspondente logo após a base.
- Sincronize a combinação de arquivos com as variáveis de ambiente (`env/local/<instância>.env`).
- Revalide as combinações com [`scripts/validate_compose.sh`](./OPERATIONS.md#scriptsvalidate_composesh) ao alterar qualquer arquivo em `compose/`.
