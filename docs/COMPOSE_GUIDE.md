# Guia de combinações do Docker Compose

> Parte do [índice da documentação](./README.md). Leia a [Visão Geral](./OVERVIEW.md) para entender os papéis das instâncias e alinhe checklists com os runbooks da [core](./core.md) e da [media](./media.md).

Este guia documenta como montar o manifesto do Docker Compose usando apenas o
arquivo base, o override global da instância e os manifests específicos de
cada aplicação. Para uma visão resumida da ordem de carregamento, consulte o
[README de `compose/`](../compose/README.md). Siga estas instruções antes de
executar `docker compose`.

> **Atenção para forks:** todos os caminhos `compose/...` mostrados aqui são
> exemplos. Ajuste nomes de diretórios, arquivos e serviços conforme o passo 3
> de [Como iniciar um projeto derivado](../README.md#como-iniciar-um-projeto-derivado)
> ao adaptar o template para a sua stack.

## Estrutura dos manifests

| Tipo de arquivo | Localização | Papel |
| --------------- | ----------- | ----- |
| **Base** | `compose/base.yml` (opcional) | Mantém apenas anchors e volumes compartilhados reutilizados pelas aplicações. É carregado automaticamente quando existir; se estiver ausente, o plano começa diretamente pelos manifests da instância. |
| **Instância (global)** | `compose/<instância>.yml` (ex.: [`compose/core.yml`](../compose/core.yml), [`compose/media.yml`](../compose/media.yml)) *(opcional)* | Reúne ajustes compartilhados por todas as aplicações daquela instância (ex.: redes extras, volumes padrão ou labels globais). Quando o arquivo existir, ele é aplicado imediatamente após o manifesto base para que os recursos sejam sobrescritos antes dos manifests das aplicações. |
| **Aplicação** | `compose/apps/<app>/base.yml` | Declara os serviços adicionais que compõem uma aplicação (ex.: `app`). Usa os anchors definidos em `compose/base.yml`. Substitua `<app>` pelo diretório da sua aplicação principal (ex.: `compose/apps/<sua-app>/base.yml`). É incluído automaticamente para todas as instâncias **quando o arquivo existir**. |
| **Overrides da aplicação** | `compose/apps/<app>/<instância>.yml` | Especializa os serviços da aplicação para cada ambiente (nome do container, portas, variáveis específicas como `APP_PUBLIC_URL` ou `MEDIA_ROOT`). Cada instância possui um arquivo por aplicação (ex.: `compose/apps/<sua-app>/core.yml`). |

> **Observação:** aplicações que têm apenas `base.yml` são carregadas automaticamente em **todas** as instâncias. Para restringir a execução a um subconjunto específico, crie um override por instância (mesmo que o conteúdo seja apenas `profiles` ou `deploy.replicas: 0`) ou mova os manifests para um diretório override-only.

Exemplo de stub para desativar uma aplicação na instância `media`:

1. Crie o arquivo `compose/apps/<app>/media.yml` (substitua `<app>` pelo diretório real da aplicação).
2. Insira apenas os campos necessários para ajustar o serviço alvo, como no exemplo abaixo, definindo `deploy.replicas: 0`:

```yaml
# compose/apps/<app>/media.yml
services:
  <serviço-principal>:
    deploy:
      replicas: 0
```

> Ajuste `<serviço-principal>` para o nome do serviço declarado em `compose/apps/<app>/base.yml`. Esse stub mantém o serviço ativo nas demais instâncias (com override próprio) e o desativa apenas em `media`.

### Exemplos incluídos no template

- Quando presente, [`compose/core.yml`](../compose/core.yml) documenta como adicionar labels para um proxy reverso, conectar os serviços da instância a uma rede externa (`core_proxy`) e declarar volumes nomeados (`core_logs`).
- Quando presente, [`compose/media.yml`](../compose/media.yml) mostra como compartilhar montagens de mídia (`MEDIA_HOST_PATH`) entre serviços e como definir um volume comum para caches de transcodificação (`media_cache`).

### Aplicações compostas apenas por overrides

Nem toda aplicação precisa de um `base.yml`. Algumas stacks reutilizam serviços
existentes e aplicam apenas ajustes específicos por instância (por exemplo,
adicionando rótulos, redes extras ou variáveis). Nestes casos, o diretório da
aplicação é considerado **override-only**.

#### Como preparar o diretório

1. Crie o diretório `compose/apps/<app>/` normalmente.
2. Adicione pelo menos um arquivo `compose/apps/<app>/<instância>.yml` com os
   serviços e ajustes específicos daquela instância.
3. Omitir `compose/apps/<app>/base.yml` é aceitável. Sempre que o diretório não
   contiver esse arquivo, os scripts assumem automaticamente que a aplicação é
   override-only e não tentam anexar um manifest inexistente ao plano.

#### Geração automática com `bootstrap_instance`

Use `scripts/bootstrap_instance.sh <app> <instância> --override-only` para
gerar apenas o override e o arquivo de variáveis quando estiver montando uma
aplicação sem `base.yml`. Se o diretório da aplicação já existir sem um arquivo
base, o script detecta o modo override-only automaticamente ao adicionar novas
instâncias, evitando a criação de artefatos redundantes.

#### Como os scripts tratam overrides puros

- `scripts/lib/compose_discovery.sh` identifica diretórios override-only e
  registra somente os arquivos `<instância>.yml` existentes.
- Durante a geração do plano (`scripts/lib/compose_plan.sh`), apenas esses
  overrides são encadeados após `compose/base.yml` (quando presente) e os ajustes globais da
  instância, preservando a ordem dos demais manifests.
- O mapa `COMPOSE_APP_BASE_FILES`, exportado por
  `scripts/lib/compose_instances.sh`, mantém apenas aplicações com `base.yml`
  real. Diretórios override-only ficam fora desse mapa e, portanto, não
  introduzem referências quebradas nas validações ou comandos `docker compose`.

## Stacks com múltiplas aplicações

Ao combinar diversas aplicações, carregue os manifests em blocos (`base.yml`, `base.yml` da aplicação e override da instância) na ordem mostrada abaixo. Isso garante que anchors e variáveis fiquem disponíveis antes dos serviços que os consomem.

| Ordem | Arquivo | Função |
| ----- | ------- | ------ |
| 1 | `compose/base.yml` (quando existir) | Estrutura fundacional com anchors compartilhados. |
| 2 | `compose/<instância>.yml` (ex.: `compose/core.yml`, `compose/media.yml`) *(quando existir)* | Ajustes globais da instância (labels, redes extras, políticas padrões). |
| 3 | `compose/apps/<app-principal>/base.yml` (ex.: `compose/apps/app/base.yml`) | Define serviços da aplicação principal. |
| 4 | `compose/apps/<app-principal>/<instância>.yml` (ex.: `compose/apps/app/core.yml`) | Ajusta a aplicação principal para a instância alvo. |
| 5 | `compose/apps/<app-auxiliar>/base.yml` (ex.: `compose/apps/monitoring/base.yml`) | Declara serviços auxiliares (ex.: observabilidade). |
| 6 | `compose/apps/<app-auxiliar>/<instância>.yml` (ex.: `compose/apps/monitoring/core.yml`) | Personaliza os serviços auxiliares para a instância. |
| 7 | `compose/apps/<outro-app>/base.yml` (ex.: `compose/apps/worker/base.yml`) | Introduz workers assíncronos que dependem da aplicação principal. |
| 8 | `compose/apps/<outro-app>/<instância>.yml` (ex.: `compose/apps/worker/core.yml`) | Ajusta nome/concurrência dos workers por instância. |
| 9 | `compose/apps/<outra-app>/...` | Repita o padrão para cada aplicação extra adicionada. |

> Se uma aplicação não tiver `base.yml`, pule o passo correspondente e mantenha
> apenas o override (`compose/apps/<app>/<instância>.yml`). Os scripts do
> template fazem esse ajuste automaticamente ao gerar o plano.

> **Substitua os placeholders:** `app`, `monitoring`, `worker` e quaisquer
> outros nomes usados nas tabelas e exemplos representam apenas diretórios
> ilustrativos. Ajuste cada ocorrência ao nome real da sua aplicação seguindo o
> passo 3 de [Como iniciar um projeto derivado](../README.md#como-iniciar-um-projeto-derivado).

### Snippet base para combinar manifests

Use o esqueleto abaixo em qualquer instância, preenchendo o placeholder
`<instância>` e adicionando apenas as aplicações desejadas. Quando precisar de
overlays extras (ex.: `compose/overlays/metrics.yml`), liste-os na variável
`COMPOSE_EXTRA_FILES` separados por espaço antes de executar o comando. O
snippet converte automaticamente cada entrada em um novo `-f`.

```bash
docker compose \
  --env-file env/local/common.env \
  --env-file env/local/<instância>.env \
  -f compose/base.yml \  # Inclua somente se o arquivo existir
  -f compose/<instância>.yml \ # Inclua somente se o arquivo existir (ex.: compose/core.yml)
  -f compose/apps/<app-principal>/base.yml \
  -f compose/apps/<app-principal>/<instância>.yml \
  # Opcional: adicione pares base/instância para cada aplicação auxiliar habilitada
  -f compose/apps/<aplicação-opcional>/base.yml \
  -f compose/apps/<aplicação-opcional>/<instância>.yml \
  $(for file in ${COMPOSE_EXTRA_FILES:-}; do printf ' -f %s' "$file"; done) \
  up -d
```

> Exemplo: substitua `<app-principal>` pelo diretório real da sua aplicação
> (como `compose/apps/app/`). Sincronize nomes e caminhos conforme o passo 3 de
> [Como iniciar um projeto derivado](../README.md#como-iniciar-um-projeto-derivado).

> `COMPOSE_EXTRA_FILES` deve conter overlays adicionais (ex.: arquivos em
> `compose/overlays/`) listados em ordem. Defina a variável com `export` ou
> inline (`COMPOSE_EXTRA_FILES="compose/overlays/metrics.yml" docker compose ...`)
> para anexar os manifests extras à pilha.

#### Como habilitar ou desativar aplicações auxiliares

- **Manter ativa**: preserve o par `base.yml`/`<instância>.yml` correspondente no
  snippet (ex.: `monitoring` → `-f compose/apps/monitoring/base.yml` +
  `-f compose/apps/monitoring/<instância>.yml`).
- **Desativar seletivamente**: mantenha um override explícito para cada instância
  onde o serviço deve ser desligado (ex.: `compose/apps/monitoring/media.yml`
  com `deploy.replicas: 0` ou `profiles` específicos). Essa abordagem garante
  que os scripts continuem carregando a aplicação apenas onde ela estiver
  habilitada e evita a ativação acidental em novas instâncias.
- **Remover globalmente**: exclua o par de linhas quando a aplicação deixar de
  fazer parte da stack em **todas** as instâncias.
- **Adicionar outra aplicação**: replique as duas linhas substituindo
  `<aplicação-opcional>` pelo diretório em `compose/apps/<app>/`.

> **Importante:** ao executar o Compose manualmente, replique a mesma cadeia de
> arquivos `.env` usada pelos scripts (`env/local/common.env` seguido de
> `env/local/<instância>.env`). Consulte o passo a passo em
> [`env/README.md#como-gerar-arquivos-locais`](../env/README.md#como-gerar-arquivos-locais)
> para garantir que variáveis globais obrigatórias não sejam omitidas. Além
> disso, exporte `LOCAL_INSTANCE=<instância>` (o wrapper faz isso automaticamente)
> antes de chamar `docker compose` para preservar o sufixo `data/app-<instância>`
> nos volumes.

As diferenças entre as instâncias principais ficam concentradas nos arquivos
carregados e nas variáveis apontadas pelo comando acima:

| Cenário | `--env-file` (ordem) | Overrides obrigatórios (`-f`) | Overlays adicionais | Observações |
| ------- | -------------------- | ----------------------------- | ------------------- | ----------- |
| **core** | `env/local/common.env` → `env/local/core.env` | `compose/core.yml` (quando existir), `compose/apps/<app-principal>/core.yml` (ex.: `compose/apps/app/core.yml`) | — | Sem overlays obrigatórios. Utilize apenas quando a stack demandar arquivos extras. |
| **media** | `env/local/common.env` → `env/local/media.env` | `compose/media.yml` (quando existir), `compose/apps/<app-principal>/media.yml` (ex.: `compose/apps/app/media.yml`) | Opcional: `compose/overlays/<overlay>.yml` (ex.: armazenamento de mídia) | Adicione overlays específicos da instância listando-os em `COMPOSE_EXTRA_FILES` antes de executar o comando. |

### Combinação ad-hoc com `COMPOSE_FILES`

```bash
export COMPOSE_FILES="compose/base.yml compose/media.yml compose/apps/<app-principal>/base.yml compose/apps/<app-principal>/media.yml" # Remova entradas inexistentes
docker compose \
  --env-file env/local/common.env \
  --env-file env/local/media.env \
  $(for file in $COMPOSE_FILES; do printf ' -f %s' "$file"; done) \
  up -d
```

> Ajuste `<app-principal>` para o diretório da sua aplicação (ex.: `compose/apps/app/`).
> O alinhamento dos manifests com o passo 3 de [Como iniciar um projeto derivado](../README.md#como-iniciar-um-projeto-derivado)
> evita caminhos desatualizados após renomear serviços.

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

> O diretório `compose/apps/app/` abaixo é ilustrativo. Adapte para o nome da
> sua aplicação principal e valide os manifests conforme o passo 3 de [Como
> iniciar um projeto derivado](../README.md#como-iniciar-um-projeto-derivado).

```
Instância: core

Arquivos Compose (-f):
  • compose/base.yml
  • compose/core.yml
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

> Alinhe qualquer caminho `compose/...` citado abaixo com o passo 3 de [Como
> iniciar um projeto derivado](../README.md#como-iniciar-um-projeto-derivado)
> sempre que renomear aplicações ou instâncias no seu fork.

- Sempre carregue `compose/base.yml` em primeiro lugar.
- Quando existir, aplique `compose/<instância>.yml` logo após o arquivo base.
- Inclua os arquivos `compose/apps/<app>/base.yml` antes dos overrides por instância **quando existirem**.
- Combine o override `compose/apps/<app>/<instância>.yml` correspondente logo após o `base.yml` da aplicação.
- Sincronize a combinação de arquivos com a cadeia de variáveis de ambiente (`env/local/common.env` → `env/local/<instância>.env`).
- Revalide as combinações com [`scripts/validate_compose.sh`](./OPERATIONS.md#scriptsvalidate_compose.sh) ao alterar qualquer arquivo em `compose/`.
