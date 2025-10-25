# Guia de combinações do Docker Compose

> Parte do [índice da documentação](./README.md). Leia a [Visão Geral](./OVERVIEW.md) para entender os papéis das instâncias e alinhe checklists com os runbooks da [core](./core.md) e da [media](./media.md).

Este guia documenta como montar o manifesto do Docker Compose usando apenas os
arquivos base e os overrides por instância. Siga estas instruções antes de
executar `docker compose` ou os scripts em `scripts/*.sh`.

## Estrutura dos manifests

| Tipo de arquivo | Localização | Papel |
| --------------- | ----------- | ----- |
| **Base** | `compose/base.yml` | Mantém apenas anchors e volumes compartilhados reutilizados pelas aplicações. Deve ser carregado **sempre** como primeiro manifesto. |
| **Aplicação** | `compose/apps/<app>/base.yml` | Declara os serviços adicionais que compõem uma aplicação (ex.: `app`). Usa os anchors definidos em `compose/base.yml`. É incluído automaticamente para todas as instâncias. |
| **Overrides de instância** | `compose/apps/<app>/<instância>.yml` | Especializa os serviços da aplicação para cada ambiente (nome do container, portas, variáveis específicas como `APP_PUBLIC_URL` ou `MEDIA_ROOT`). Cada instância possui um arquivo por aplicação (ex.: `compose/apps/app/core.yml`). |

## Stacks com múltiplas aplicações

Ao combinar diversas aplicações, carregue os manifests em blocos (`base.yml`, `base.yml` da aplicação e override da instância) na ordem mostrada abaixo. Isso garante que anchors e variáveis fiquem disponíveis antes dos serviços que os consomem.

| Ordem | Arquivo | Função |
| ----- | ------- | ------ |
| 1 | `compose/base.yml` | Estrutura fundacional com anchors compartilhados. |
| 2 | `compose/apps/app/base.yml` | Define serviços da aplicação principal. |
| 3 | `compose/apps/app/<instância>.yml` | Ajusta a aplicação principal para a instância alvo. |
| 4 | `compose/apps/monitoring/base.yml` | Declara serviços auxiliares (ex.: observabilidade). |
| 5 | `compose/apps/monitoring/<instância>.yml` | Personaliza os serviços auxiliares para a instância. |
| 6 | `compose/apps/<outra-app>/...` | Repita o padrão para cada aplicação extra adicionada. |

### Exemplo: stack completa na instância core

```bash
docker compose \
  --env-file env/local/core.env \
  -f compose/base.yml \
  -f compose/apps/app/base.yml \
  -f compose/apps/app/core.yml \
  -f compose/apps/monitoring/base.yml \
  -f compose/apps/monitoring/core.yml \
  up -d
```

### Exemplo: desativando uma aplicação auxiliar

Para subir apenas a aplicação principal, omita o par `monitoring` (ou outro diretório em `compose/apps/`).

```bash
docker compose \
  --env-file env/local/media.env \
  -f compose/base.yml \
  -f compose/apps/app/base.yml \
  -f compose/apps/app/media.yml \
  up -d
```

## Exemplos de comando

### Core

```bash
docker compose \
  --env-file env/local/core.env \
  -f compose/base.yml \
  -f compose/apps/app/base.yml \
  -f compose/apps/app/core.yml \
  up -d
```

### Media (com volume de mídia)

```bash
docker compose \
  --env-file env/local/media.env \
  -f compose/base.yml \
  -f compose/apps/app/base.yml \
  -f compose/apps/app/media.yml \
  up -d
```

### Combinação ad-hoc com `COMPOSE_FILES`

```bash
export COMPOSE_FILES="compose/base.yml compose/apps/app/base.yml compose/apps/app/media.yml"
docker compose \
  --env-file env/local/media.env \
  $(for file in $COMPOSE_FILES; do printf ' -f %s' "$file"; done) \
  up -d
```

## Boas práticas

- Sempre carregue `compose/base.yml` em primeiro lugar.
- Inclua todos os arquivos `compose/apps/<app>/base.yml` antes dos overrides por instância.
- Combine o override `compose/apps/<app>/<instância>.yml` correspondente logo após o `base.yml` da aplicação.
- Sincronize a combinação de arquivos com as variáveis de ambiente (`env/local/<instância>.env`).
- Revalide as combinações com [`scripts/validate_compose.sh`](./OPERATIONS.md#scriptsvalidate_composesh) ao alterar qualquer arquivo em `compose/`.
