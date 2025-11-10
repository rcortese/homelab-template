# Guia rápido de manifests Compose

> Consulte também o [Guia de combinações do Docker Compose](../docs/COMPOSE_GUIDE.md) para instruções completas
> e o panorama da [estrutura do template](../docs/STRUCTURE.md).

## Ordem de carregamento recomendada

Os manifests são encadeados em blocos. Cada passo herda anchors e variáveis do anterior.

1. `compose/base.yml` *(opcional)* — define anchors, volumes nomeados e variáveis compartilhadas. É carregado automaticamente
   quando existir.
2. Manifesto da instância (`compose/<instância>.yml`, ex.: `compose/core.yml`) *(opcional)* — ativa redes, labels e volumes
   globais quando presente.
3. Aplicações habilitadas (`compose/apps/<app>/...`) — cada aplicação entra como um par `base.yml` + `<instância>.yml`.

```
(base.yml) → core.yml|media.yml → compose/apps/app/base.yml → compose/apps/app/<instância>.yml → ...
```

> Os scripts (`scripts/compose.sh`, `scripts/deploy_instance.sh`, etc.) respeitam automaticamente essa ordem ao montar o plano.

## Instâncias principais e aplicações opcionais

- **Instâncias principais:** `core` e `media` são exemplos de perfis completos. Seus manifests (`compose/core.yml` e
  `compose/media.yml`, quando existentes) carregam ajustes compartilhados por todas as aplicações daquela instância (labels de
  proxy, redes externas, montagens de mídia, caches, etc.).
- **Aplicação principal:** `compose/apps/app/` ilustra uma aplicação padrão. O arquivo `base.yml` introduz serviços e anchors que
  serão especializados nos overrides `core.yml` e `media.yml`.
- **Aplicações auxiliares:** diretórios como `compose/apps/monitoring/` e `compose/apps/worker/` mostram como habilitar componentes
  opcionais. Basta incluir o par `base.yml` + `<instância>.yml` desejado após o manifesto da instância ativa. Serviços sem
  `base.yml` são tratados como *override-only* e só são anexados às instâncias onde o arquivo existe.

Ao montar a pilha, escolha quais blocos de aplicação anexar. A instância `core` pode rodar `app` + `monitoring`, enquanto `media`
carrega apenas `app` + `worker`, por exemplo. Mantendo a ordem, anchors definidos em `compose/base.yml` (quando presente)
permanecem disponíveis para qualquer combinação.

## Variáveis de ambiente essenciais

| Variável | Onde definir | Finalidade | Referência |
| --- | --- | --- | --- |
| `TZ` | `env/common.example.env` | Garante timezone consistente para logs e agendamentos. | [env/README.md](../env/README.md#envcommonexampleenv) |
| `APP_DATA_DIR` / `APP_DATA_DIR_MOUNT` | `env/common.example.env` | Define o caminho persistente (relativo ou absoluto) utilizado pelos manifests. | [env/README.md](../env/README.md#envcommonexampleenv) |
| `APP_SHARED_DATA_VOLUME_NAME` | `env/common.example.env` | Padroniza o volume compartilhado entre múltiplas aplicações. | [env/README.md](../env/README.md#envcommonexampleenv) |
| `COMPOSE_EXTRA_FILES` | `env/<instância>.example.env` | Lista overlays adicionais aplicados após os manifests padrão. | [env/README.md](../env/README.md#como-gerar-arquivos-locais) |

> Use o [guia completo de variáveis de ambiente](../env/README.md) para revisar a lista atualizada e documentar novos campos.
> Placeholders do app e do worker de exemplo (como `APP_SECRET`, `APP_RETENTION_HOURS` e `WORKER_QUEUE_URL`) estão detalhados na seção correspondente do [README de `env/`](../env/README.md#placeholders-app-worker).

## Ferramenta de inspeção

Execute `scripts/describe_instance.sh <instância>` para auditar os manifests carregados, serviços ativos, portas expostas e volumes
resultantes a partir de `docker compose config`. A flag `--list` revela as instâncias disponíveis e `--format json` exporta os
metadados para automação.

