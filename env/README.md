# Guia de variáveis de ambiente

Este diretório armazena modelos (`*.example.env`) e instruções para gerar arquivos locais em `env/local/`. Repositórios derivados devem adaptar estes exemplos ao seu conjunto de serviços, mantendo a documentação atualizada.

## Como gerar arquivos locais

1. Crie o diretório ignorado pelo Git:
   ```bash
   mkdir -p env/local
   ```
2. Copie o modelo compartilhado para servir como base global:
   ```bash
   cp env/common.example.env env/local/common.env
   ```
3. Copie os modelos específicos de cada instância que será utilizada:
   ```bash
   cp env/<alvo>.example.env env/local/<alvo>.env
   ```
4. Preencha os valores conforme o ambiente (desenvolvimento, laboratório, produção, etc.).

> **Dica:** as variáveis definidas em `env/local/common.env` são carregadas antes das instâncias (ex.: `env/local/core.env`). Utilize esse arquivo para consolidar credenciais compartilhadas, fuso horário, UID/GID de volumes e demais defaults globais.

## Mapeamento das variáveis

### `env/common.example.env`

#### Variáveis do template base

| Variável | Obrigatória? | Uso | Referência |
| --- | --- | --- | --- |
| `TZ` | Sim | Define timezone para logs e agendamentos. | `compose/apps/app/base.yml`. |
| `APP_DATA_DIR`/`APP_DATA_DIR_MOUNT` | Opcional | Define o diretório persistente relativo (`data/<app>-<instância>`) ou um caminho absoluto alternativo — nunca use ambos ao mesmo tempo. | `scripts/deploy_instance.sh`, `scripts/compose.sh`, `scripts/backup.sh`, `scripts/fix_permission_issues.sh`. |
| `APP_DATA_UID`/`APP_DATA_GID` | Opcional | Ajusta o proprietário padrão dos volumes persistentes. | `scripts/deploy_instance.sh`, `scripts/backup.sh`, `scripts/fix_permission_issues.sh`. |
| `APP_NETWORK_NAME` | Opcional | Nome lógico da rede compartilhada entre as aplicações. | `compose/base.yml`. |
| `APP_NETWORK_DRIVER` | Opcional | Driver utilizado ao criar a rede compartilhada (ex.: `bridge`, `macvlan`). | `compose/base.yml`. |
| `APP_NETWORK_SUBNET` | Opcional | Sub-rede reservada para os serviços internos. | `compose/base.yml`. |
| `APP_NETWORK_GATEWAY` | Opcional | Gateway disponibilizado aos contêineres na sub-rede acima. | `compose/base.yml`. |
| `APP_SHARED_DATA_VOLUME_NAME` | Opcional | Personaliza o volume persistente compartilhado entre aplicações. | `compose/base.yml`. |

<a id="placeholders-app-worker"></a>

#### Placeholders das aplicações de exemplo (`app`/`worker`)

| Variável | Obrigatória? | Uso | Referência |
| --- | --- | --- | --- |
| `APP_SECRET` | Sim | Chave utilizada para criptografar dados sensíveis. | `compose/apps/app/base.yml`. |
| `APP_RETENTION_HOURS` | Opcional | Controla a retenção de registros/processos. | `compose/apps/app/base.yml` e runbooks. |
| `WORKER_QUEUE_URL` | Opcional | Origem da fila de tarefas processada pelos workers de exemplo. | `compose/apps/worker/base.yml`. |

> Ao adaptar a stack, renomeie ou remova esses placeholders para refletir o nome real das suas aplicações e ajuste os manifests correspondentes (`compose/apps/<sua-app>/` e `compose/apps/worker/`). Manter os nomes genéricos `APP_*` facilita entender o template, mas os forks devem alinhar a nomenclatura com o domínio do projeto (por exemplo, `PORTAL_SECRET`, `PORTAL_RETENTION_HOURS`, `PAYMENTS_QUEUE_URL`).

Monte uma tabela semelhante à abaixo para cada arquivo `env/<alvo>.example.env`:

| Variável | Obrigatória? | Uso | Referência |
| --- | --- | --- | --- |
| `APP_PUBLIC_URL` | Opcional | Define URL pública para links e cookies. | `compose/apps/<app>/<instância>.yml` (ex.: `compose/apps/app/core.yml`). |
| `COMPOSE_EXTRA_FILES` | Opcional | Lista overlays adicionais aplicados após o override da instância (separados por espaço ou vírgula). | `scripts/deploy_instance.sh`, `scripts/validate_compose.sh`, `scripts/lib/compose_defaults.sh`. |

> Substitua a tabela pelos campos reais da sua stack. Utilize a coluna **Referência** para apontar onde a variável é consumida (manifests, scripts, infraestrutura externa, etc.).

Os modelos de instância incluem placeholders ilustrativos que devem ser renomeados conforme o serviço real de cada fork. Utilize a lista a seguir como guia ao revisar `env/core.example.env` e `env/media.example.env`:

- `APP_PUBLIC_URL` e `APP_WEBHOOK_URL` — URLs injetadas na aplicação principal (`compose/apps/app/core.yml`).
- `APP_CORE_PORT` e `APP_MEDIA_PORT` — mapeamentos de porta expostos pelos manifests específicos da instância (`compose/apps/app/core.yml` e `compose/apps/app/media.yml`).
- `APP_NETWORK_IPV4` — endereço estático utilizado pelo serviço principal nas redes internas (`compose/apps/app/base.yml`).
- `MONITORING_NETWORK_IPV4` — IP reservado para o serviço de monitoramento de exemplo (`compose/apps/monitoring/base.yml` e `compose/apps/monitoring/core.yml`).
- `WORKER_CORE_CONCURRENCY`, `WORKER_MEDIA_CONCURRENCY`, `WORKER_CORE_NETWORK_IPV4` e `WORKER_MEDIA_NETWORK_IPV4` — variáveis consumidas pelos manifests dos workers (`compose/apps/worker/core.yml` e `compose/apps/worker/media.yml`).
- `CORE_PROXY_NETWORK_NAME`, `CORE_PROXY_IPV4` e `CORE_LOGS_VOLUME_NAME` — recursos compartilhados definidos na instância `core` (`compose/core.yml`).
- `MEDIA_HOST_PATH` e `MEDIA_CACHE_VOLUME_NAME` — montagens e volumes específicos da instância `media` (`compose/apps/app/media.yml` e `compose/media.yml`).

Renomeie esses identificadores para termos alinhados ao seu domínio (por exemplo, `PORTAL_PUBLIC_URL`, `PORTAL_NETWORK_IPV4`, `ACME_PROXY_NETWORK_NAME`) e atualize os manifests associados para evitar resíduos do exemplo padrão.

> **Nota:** o diretório persistente principal segue a convenção `data/<app>-<instância>`, considerando a aplicação principal (primeira da lista em `COMPOSE_INSTANCE_APP_NAMES`). Deixe `APP_DATA_DIR` e `APP_DATA_DIR_MOUNT` em branco para usar automaticamente esse fallback relativo. Informe **apenas um** deles quando precisar personalizar o caminho (relativo ou absoluto, respectivamente); os scripts retornam erro se ambos estiverem definidos ao mesmo tempo. Ajuste `APP_DATA_UID` e `APP_DATA_GID` para alinhar permissões.

> **Novo fluxo (`LOCAL_INSTANCE`)**: os wrappers (`scripts/compose.sh`, `scripts/deploy_instance.sh`, etc.) exportam automaticamente `LOCAL_INSTANCE` com base no arquivo `.env` da instância ativa (ex.: `core`, `media`). Essa variável substitui o sufixo de `data/app-<instância>` nos manifests. Ao executar `docker compose` diretamente, exporte `LOCAL_INSTANCE=<instância>` antes do comando ou reutilize os scripts para evitar divergências de diretórios.

## Boas práticas

- **Padronize nomes**: utilize prefixos (`APP_`, `DB_`, `CACHE_`) para agrupar responsabilidades.
- **Documente defaults seguros**: indique valores recomendados ou formatos esperados (ex.: URLs completas, chaves com tamanho mínimo).
- **Evite segredo no Git**: mantenha apenas modelos e documentação. Os arquivos em `env/local/` devem estar listados no `.gitignore`.
- **Sincronize com ADRs**: se novas variáveis forem introduzidas por decisões arquiteturais, referencie o ADR correspondente na tabela.

## Integração com scripts

Os scripts fornecidos pelo template aceitam `COMPOSE_ENV_FILES` (ou o legado `COMPOSE_ENV_FILE`) para selecionar quais arquivos `.env` serão utilizados. Documente, no runbook correspondente, como combinar variáveis e manifests para cada ambiente. Quando precisar ativar overlays específicos sem modificar scripts, adicione no `.env` algo como:

```env
COMPOSE_EXTRA_FILES=compose/overlays/observability.yml compose/overlays/metrics.yml
```

Esse padrão mantém as diferenças entre template e fork confinadas aos arquivos de configuração. Quando múltiplos arquivos `.env` são carregados (globais + específicos), os valores definidos por último prevalecem.
