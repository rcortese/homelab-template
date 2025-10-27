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

| Variável | Obrigatória? | Uso | Referência |
| --- | --- | --- | --- |
| `TZ` | Sim | Define timezone para logs e agendamentos. | `compose/apps/app/base.yml`. |
| `APP_SECRET` | Sim | Chave utilizada para criptografar dados sensíveis. | `compose/apps/app/base.yml`. |
| `APP_RETENTION_HOURS` | Opcional | Controla a retenção de registros/processos. | `compose/apps/app/base.yml` e runbooks. |
| `APP_DATA_DIR`/`APP_DATA_DIR_MOUNT` | Opcional | Define o diretório persistente relativo (`data/<app>-<instância>`) ou um caminho absoluto alternativo — nunca use ambos ao mesmo tempo. | `scripts/deploy_instance.sh`, `scripts/compose.sh`, `scripts/backup.sh`, `scripts/fix_permission_issues.sh`. |
| `APP_DATA_UID`/`APP_DATA_GID` | Opcional | Ajusta o proprietário padrão dos volumes persistentes. | `scripts/deploy_instance.sh`, `scripts/backup.sh`, `scripts/fix_permission_issues.sh`. |
| `APP_INSTANCE`/`APP_PRIMARY_APP` | Automático | Identificadores derivados pelos helpers. Alimentam a convenção `data/<app>-<instância>` e tornam o slug da aplicação disponível para scripts e manifests. | `scripts/lib/deploy_context.sh`, `scripts/compose.sh`, `compose/apps/app/base.yml`. |
| `APP_SHARED_DATA_VOLUME_NAME` | Opcional | Personaliza o volume persistente compartilhado entre aplicações. | `compose/base.yml`. |

Monte uma tabela semelhante à abaixo para cada arquivo `env/<alvo>.example.env`:

| Variável | Obrigatória? | Uso | Referência |
| --- | --- | --- | --- |
| `APP_PUBLIC_URL` | Opcional | Define URL pública para links e cookies. | `compose/apps/<app>/<instância>.yml` (ex.: `compose/apps/app/core.yml`). |
| `COMPOSE_EXTRA_FILES` | Opcional | Lista overlays adicionais aplicados após o override da instância (separados por espaço ou vírgula). | `scripts/deploy_instance.sh`, `scripts/validate_compose.sh`, `scripts/lib/compose_defaults.sh`. |

> Substitua a tabela pelos campos reais da sua stack. Utilize a coluna **Referência** para apontar onde a variável é consumida (manifests, scripts, infraestrutura externa, etc.).

> **Nota:** o diretório persistente principal segue a convenção `data/<app>-<instância>`, considerando a aplicação principal (primeira da lista em `COMPOSE_INSTANCE_APP_NAMES`). Os helpers exportam `APP_PRIMARY_APP` e `APP_INSTANCE` automaticamente para compor esse slug. Deixe `APP_DATA_DIR` e `APP_DATA_DIR_MOUNT` em branco para usar automaticamente esse fallback relativo. Informe **apenas um** deles quando precisar personalizar o caminho (relativo ou absoluto, respectivamente); os scripts retornam erro se ambos estiverem definidos ao mesmo tempo. Ajuste `APP_DATA_UID` e `APP_DATA_GID` para alinhar permissões.

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
