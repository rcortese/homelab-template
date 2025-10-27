# Guia de combinações do Docker Compose

> Parte do [índice da documentação](./README.md). Leia a [Visão Geral](./OVERVIEW.md) para entender os papéis das instâncias e alinhe checklists com os runbooks da [core](./core.md) e da [media](./media.md).

Este guia documenta como montar o manifesto do Docker Compose usando apenas os
arquivos base e os overrides por instância. Siga estas instruções antes de
executar `docker compose`.

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
| 6 | `compose/apps/worker/base.yml` | Introduz workers assíncronos que dependem da aplicação principal. |
| 7 | `compose/apps/worker/<instância>.yml` | Ajusta nome/concurrência dos workers por instância. |
| 8 | `compose/apps/<outra-app>/...` | Repita o padrão para cada aplicação extra adicionada. |

### Exemplo: stack completa na instância core

```bash
docker compose \
  --env-file env/local/common.env \
  --env-file env/local/core.env \
  -f compose/base.yml \
  -f compose/apps/app/base.yml \
  -f compose/apps/app/core.yml \
  -f compose/apps/monitoring/base.yml \
  -f compose/apps/monitoring/core.yml \
  -f compose/apps/worker/base.yml \
  -f compose/apps/worker/core.yml \
  up -d
```

### Exemplo: desativando uma aplicação auxiliar

Para subir apenas a aplicação principal, omita os pares `monitoring` e `worker` (ou outro diretório em `compose/apps/`).

```bash
docker compose \
  --env-file env/local/common.env \
  --env-file env/local/media.env \
  -f compose/base.yml \
  -f compose/apps/app/base.yml \
  -f compose/apps/app/media.yml \
  up -d
```

## Exemplos de comando

Use um único esqueleto de comando e ajuste os parâmetros marcados para cada
instância:

```bash
docker compose \
  --env-file env/local/common.env \
  --env-file env/local/<instância>.env \
  -f compose/base.yml \
  -f compose/apps/app/base.yml \
  -f compose/apps/app/<instância>.yml \
  -f compose/apps/monitoring/base.yml \
  -f compose/apps/monitoring/<instância>.yml \
  -f compose/apps/worker/base.yml \
  -f compose/apps/worker/<instância>.yml \
  ${COMPOSE_EXTRA_FLAGS:-} \
  up -d
```

> `COMPOSE_EXTRA_FLAGS` pode incluir `-f` adicionais (ex.: overlays) ou outras
> opções globais necessárias para a instância.

> **Importante:** ao executar o Compose manualmente, replique a mesma cadeia de
> arquivos `.env` usada pelos scripts (`env/local/common.env` seguido de
> `env/local/<instância>.env`). Consulte o passo a passo em
> [`env/README.md#como-gerar-arquivos-locais`](../env/README.md#como-gerar-arquivos-locais)
> para garantir que variáveis globais obrigatórias não sejam omitidas.

As diferenças entre as instâncias principais ficam concentradas nos arquivos
carregados e nas variáveis apontadas pelo comando acima:

| Cenário | `--env-file` (ordem) | Overrides obrigatórios (`-f`) | Overlays adicionais | Observações |
| ------- | -------------------- | ----------------------------- | ------------------- | ----------- |
| **core** | `env/local/common.env` → `env/local/core.env` | `compose/apps/app/core.yml` | — | Sem overlays obrigatórios. Utilize apenas quando a stack demandar arquivos extras. |
| **media** | `env/local/common.env` → `env/local/media.env` | `compose/apps/app/media.yml` | Opcional: `compose/overlays/<overlay>.yml` (ex.: armazenamento de mídia) | Adicione overlays específicos da instância ao definir `COMPOSE_EXTRA_FLAGS` ou `COMPOSE_EXTRA_FILES`. |

### Combinação ad-hoc com `COMPOSE_FILES`

```bash
export COMPOSE_FILES="compose/base.yml compose/apps/app/base.yml compose/apps/app/media.yml"
docker compose \
  --env-file env/local/common.env \
  --env-file env/local/media.env \
  $(for file in $COMPOSE_FILES; do printf ' -f %s' "$file"; done) \
  up -d
```

### Gerando um resumo da instância

Use `scripts/describe_instance.sh` para inspecionar rapidamente os manifests aplicados,
serviços resultantes, portas publicadas e volumes montados. O script reutiliza o mesmo
planejamento de `-f` dos fluxos de deploy e validação e marca overlays adicionais carregados
via `COMPOSE_EXTRA_FILES`.

```bash
scripts/describe_instance.sh core

scripts/describe_instance.sh media --format json
```

O formato `table` (padrão) facilita revisões manuais, enquanto `--format json` é ideal
para gerar documentação automatizada ou alimentar dashboards.

Exemplo (formato `table`):

```
Instância: core

Arquivos Compose (-f):
  • compose/base.yml
  • compose/apps/app/base.yml
  • compose/apps/app/core.yml
  • compose/overlays/metrics.yml (overlay extra)

Overlays extras aplicados:
  • compose/overlays/metrics.yml

Serviços:
  - app
      Portas publicadas:
        • 8080 -> 80/tcp
      Volumes montados:
        • /srv/app/data -> /data/app (type=bind)
```

## Boas práticas

- Sempre carregue `compose/base.yml` em primeiro lugar.
- Inclua todos os arquivos `compose/apps/<app>/base.yml` antes dos overrides por instância.
- Combine o override `compose/apps/<app>/<instância>.yml` correspondente logo após o `base.yml` da aplicação.
- Sincronize a combinação de arquivos com a cadeia de variáveis de ambiente (`env/local/common.env` → `env/local/<instância>.env`).
- Revalide as combinações com [`scripts/validate_compose.sh`](./OPERATIONS.md#scriptsvalidate_compose.sh) ao alterar qualquer arquivo em `compose/`.
