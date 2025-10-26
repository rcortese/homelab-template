# Operações padrão do template

> Consulte o [índice geral](./README.md) e personalize este guia para refletir a sua stack.

Este documento apresenta um ponto de partida para descrever processos operacionais e o uso dos scripts fornecidos pelo template. Ao derivar um repositório, adapte os exemplos abaixo com comandos concretos do seu serviço.

| Script | Objetivo | Comando básico | Gatilhos recomendados |
| --- | --- | --- | --- |
| [`scripts/check_structure.sh`](#scriptscheck_structuresh) | Confirmar diretórios/arquivos obrigatórios. | `scripts/check_structure.sh` | Antes de PRs ou pipelines que reorganizam arquivos. |
| [`scripts/check_env_sync.py`](#scriptscheck_env_syncpy) | Verificar sincronização entre Compose e `env/*.example.env`. | `scripts/check_env_sync.py` | Após editar Compose ou templates `.env`; em validações locais/CI. |
| [`scripts/bootstrap_instance.sh`](#scriptsbootstrap_instancesh) | Criar estrutura inicial de aplicação/instância. | `scripts/bootstrap_instance.sh <app> <instancia>` | Ao iniciar novos serviços ou ambientes. |
| [`scripts/validate_compose.sh`](#scriptsvalidate_composesh) | Validar combinações padrão de Docker Compose. | `scripts/validate_compose.sh` | Após ajustes em manifests; etapas de CI. |
| [`scripts/deploy_instance.sh`](#scriptsdeploy_instancesh) | Orquestrar deploy guiado de instâncias. | `scripts/deploy_instance.sh <alvo>` | Deploys manuais ou automatizados. |
| [`scripts/fix_permission_issues.sh`](#scriptsfix_permission_issuessh) | Ajustar permissões de diretórios persistentes. | `scripts/fix_permission_issues.sh <instancia>` | Antes de subir serviços que usam armazenamento compartilhado. |
| [`scripts/backup.sh`](#scriptsbackupsh) | Gerar snapshot versionado da instância. | `scripts/backup.sh <instancia>` | Rotinas de backup e pré-mudanças invasivas. |
| [`scripts/compose.sh`](#scriptscomposesh) | Padronizar chamadas ao `docker compose`. | `scripts/compose.sh <subcomando>` | Operações Compose locais ou em CI. |
| [`scripts/describe_instance.sh`](#scriptsdescribe_instancesh) | Resumir serviços, portas e volumes de uma instância. | `scripts/describe_instance.sh <instancia>` | Auditorias rápidas ou geração de runbooks. |
| [`scripts/check_health.sh`](#scriptscheck_healthsh) | Conferir status dos serviços após mudanças. | `scripts/check_health.sh <instancia>` | Pós-deploy, pós-restore ou troubleshooting. |
| [`scripts/check_db_integrity.sh`](#scriptscheck_db_integritysh) | Validar integridade de bancos SQLite com pausa controlada. | `scripts/check_db_integrity.sh <instancia>` | Manutenções programadas ou investigação de falhas. |
| [`scripts/update_from_template.sh`](#scriptsupdate_from_templatesh) | Reaplicar customizações após atualizar o template. | `scripts/update_from_template.sh --remote <remote>` | Ao sincronizar forks com o upstream. |

## Antes de começar

- Garanta que os arquivos `.env` locais foram gerados a partir dos modelos descritos em [`env/README.md`](../env/README.md).
- Revise as combinações de manifests (`compose/base.yml` + overrides) que serão utilizadas pelos scripts.
- Execute `scripts/check_all.sh` para validar estrutura, sincronização de variáveis e manifests Compose antes de abrir PRs ou publicar mudanças locais.
- Execute `scripts/check_env_sync.py` isoladamente sempre que editar manifests ou templates `.env` para garantir que as variáveis continuam sincronizadas.
- Documente dependências extras (CLI, credenciais, acesso a registries) em seções adicionais.

## scripts/check_structure.sh

Consulte o resumo na tabela acima. Inclua `scripts/check_env_sync.py` nas execuções locais ou de CI para manter manifests e variáveis sincronizados.

## scripts/check_env_sync.py

- **Objetivo:** comparar os manifests (`compose/base.yml` + overrides detectados) com os arquivos `env/*.example.env` correspondentes e sinalizar divergências.
- **Uso típico:**
  ```bash
  scripts/check_env_sync.py
  scripts/check_env_sync.py --repo-root /caminho/alternativo
  ```
- **Saída:** lista variáveis ausentes, obsoletas ou instâncias sem template, retornando código de saída diferente de zero quando encontrar problemas — ideal para CI.
- **Boas práticas:** execute o script após mudanças em Compose ou nos arquivos `.env` de exemplo e inclua-o no pipeline de validação local antes de abrir PRs.
  > **Alerta:** rodar a verificação antes de abrir PRs evita que variáveis órfãs avancem para revisão.

## scripts/bootstrap_instance.sh

Use `--base-dir` para executar fora da raiz e `--with-docs` para gerar documentação inicial. Após o bootstrap, ajuste overrides (`compose/apps/<app>/<instancia>.yml`), preencha `env/<instancia>.example.env` e complemente `docs/apps/<app>.md`.

<a id="scriptsvalidate_compose.sh"></a>
## scripts/validate_compose.sh

- **Parâmetros úteis:**
  - `COMPOSE_INSTANCES` — lista de ambientes a validar (separados por espaço ou vírgula).
  - `DOCKER_COMPOSE_BIN` — caminho alternativo para o binário.
  - `COMPOSE_EXTRA_FILES` — lista opcional de overlays extras aplicados após o override padrão (aceita espaços ou vírgulas).
- **Exemplos práticos:**
  - Execução padrão, usando apenas os manifests base e override configurados:
    ```bash
    scripts/validate_compose.sh
    ```
  - Validação simultânea de múltiplas instâncias definidas em `COMPOSE_INSTANCES`:
    ```bash
    COMPOSE_INSTANCES="prod staging" scripts/validate_compose.sh
    ```
  - Aplicação de overlays extras listados em `COMPOSE_EXTRA_FILES`:
    ```bash
    COMPOSE_EXTRA_FILES="compose/overlays/metrics.yml" scripts/validate_compose.sh
    ```

  > As variáveis podem ser exportadas previamente (`export COMPOSE_INSTANCES=...`) ou prefixadas ao comando, mantendo o fluxo simples.
  > **Alerta:** use a validação para confirmar se as combinações padrão de Compose permanecem compatíveis com os perfis ativos antes de implantações ou PRs.

## scripts/deploy_instance.sh

Além das flags principais (`--force`, `--skip-structure`, `--skip-validate`, `--skip-health`), personalize prompts e combinações de arquivos para refletir ambientes reais. Defina `COMPOSE_EXTRA_FILES` no `.env` quando precisar de overlays adicionais.

## scripts/fix_permission_issues.sh

O script depende de `scripts/lib/deploy_context.sh` para calcular `APP_DATA_DIR`, `APP_DATA_UID` e `APP_DATA_GID`. Em ambientes compartilhados, combine a execução com `--dry-run` para revisar alterações antes de aplicar `chown`. Registre exceções ao padrão `data/<app>-<instância>`.

## scripts/backup.sh

- **Dependências:**
  - o `.env` da instância deve estar atualizado para que `scripts/lib/deploy_context.sh` identifique `APP_DATA_DIR`, `COMPOSE_FILES` e demais variáveis utilizadas na montagem da stack;
  - o diretório `backups/` precisa estar acessível para gravação (o script cria subpastas automaticamente, mas respeita permissões do host);
  - recomenda-se garantir que o `.env` esteja carregado (`source env/<instancia>.env`) quando houver exports adicionais exigidos pelos serviços.
- O comando padrão (`scripts/backup.sh core`) gera um snapshot completo da instância e informa o local do artefato ao final. Consulte [`docs/BACKUP_RESTORE.md`](./BACKUP_RESTORE.md) para práticas de retenção e restauração.
- **Dicas de personalização para forks:**
  - Exporte variáveis complementares (por exemplo, `EXTRA_BACKUP_PATHS` ou credenciais de repositórios externos) antes de chamar o script, permitindo que wrappers locais incluam diretórios extras ou enviem os artefatos para armazenamento remoto.
  - Ajuste o `.env` da instância para apontar `APP_DATA_DIR` ou `COMPOSE_EXTRA_FILES` específicos quando o layout de dados divergir do padrão `data/<app>-<instância>`.
  - Amplie o fluxo em wrappers externos adicionando hooks pré/pós-backup (scripts auxiliares, notificações ou compressão) mantendo a lógica central de parada/cópia/restart encapsulada aqui.

## scripts/compose.sh

Defina `COMPOSE_FILES` e `COMPOSE_ENV_FILE` para combinações personalizadas e registre exemplos específicos da sua stack conforme necessário.

## scripts/describe_instance.sh

- **Formatações disponíveis:**
  - `table` (padrão) — ideal para revisões rápidas em terminais ou runbooks.
  - `json` — voltado para integrações automatizadas e geração de documentação.
- A saída em `table` facilita revisões rápidas. Com `--format json`, campos como `compose_files`, `extra_overlays` e `services` podem alimentar geradores de runbooks ou páginas de status.
- Destaque: o relatório aponta overlays adicionais vindos de `COMPOSE_EXTRA_FILES`, facilitando auditorias sobre customizações temporárias.

## scripts/check_health.sh

- **Argumentos e variáveis suportadas:**
  - `HEALTH_SERVICES` — lista de serviços a inspecionar (separada por espaços ou vírgulas). Quando definido, limita a execução apenas aos serviços desejados.
  - `SERVICE_NAME` — nome de um serviço específico para reduzir o escopo (útil ao investigar incidentes pontuais).
  - `COMPOSE_ENV_FILE` — caminho para um arquivo `.env` alternativo a ser carregado antes de consultar o `docker compose`.
- O script complementa automaticamente a lista de serviços executando `docker compose config --services`, garantindo cobertura mesmo sem `HEALTH_SERVICES` definido.
- **Formatos de saída:**
  - `text` (padrão) — replica o comportamento histórico imprimindo o resultado de `docker compose ps` seguido dos logs recentes.
  - `json` — serializa o status dos contêineres (incluindo `docker compose ps --format json`, quando disponível) e os logs de cada serviço monitorado para consumo por pipelines ou páginas de status.
- **Persistência da saída:** use `--output <arquivo>` para gravar o relatório em disco sem abrir mão da saída padrão, facilitando integrações que versionam ou distribuem o resultado.

Exemplos práticos:

```bash
# Saída tradicional em texto
scripts/check_health.sh core

# Coleta estruturada para pipelines (ex.: GitHub Actions + jq)
scripts/check_health.sh --format json core | jq '.logs.failed'

# Gera arquivo JSON para publicar em uma página de status
scripts/check_health.sh --format json --output status/core.json core

# Usa HEALTH_SERVICES para restringir a coleta a serviços críticos
HEALTH_SERVICES="api worker" scripts/check_health.sh --format json media | jq '.compose.raw'
```

> **Dica:** combine o modo `json` com ferramentas como `jq`, `yq` ou clientes HTTP (`curl`, `gh api`) para alimentar dashboards e notificações. O campo `logs.entries[].log` traz o conteúdo em texto, enquanto `logs.entries[].log_b64` preserva os dados em Base64 para reprocessamento seguro.

## scripts/check_db_integrity.sh

- **Parâmetros úteis:**
  - `--data-dir` — diretório raiz onde os arquivos `.db` serão buscados.
  - `--no-resume` — evita retomar automaticamente os serviços ao final da verificação (útil em investigações manuais).
  - `SQLITE3_MODE` — define o backend (`container`, `binary` ou `auto`; padrão `container`).
  - `SQLITE3_CONTAINER_RUNTIME` — runtime utilizado para executar o contêiner (padrão `docker`).
  - `SQLITE3_CONTAINER_IMAGE` — imagem utilizada para o comando `sqlite3` (padrão `keinos/sqlite3:latest`).
  - `SQLITE3_BIN` — caminho para um binário local usado em modo `binary` ou como fallback.
- **Observações operacionais:**
  - Backups com sufixo `.bak` são gerados automaticamente antes de sobrescrever um banco recuperado.
  - Sempre que uma inconsistência é detectada (mesmo após recuperação), alertas são emitidos na saída de erro padrão para facilitar integrações com sistemas de monitoramento.
  - Combine com janelas de manutenção curtas, pois os serviços permanecem pausados durante toda a inspeção.

## scripts/update_from_template.sh

- **Parâmetros principais:**
  - `--remote` — nome do remote que aponta para o repositório original do template.
  - `--original-commit` — hash do commit do template usado quando o fork foi criado.
  - `--first-local-commit` — hash do primeiro commit exclusivo do repositório derivado.
  - `--dry-run` — executa apenas a simulação do rebase sem alterar a branch atual.
- Consulte a seção ["Atualizando a partir do template original"](../README.md#atualizando-a-partir-do-template-original) do `README.md` para o passo a passo completo.
- **Exemplo:**
  ```bash
  scripts/update_from_template.sh \
    --remote template \
    --original-commit <hash-do-template-inicial> \
    --first-local-commit <hash-do-primeiro-commit-local> \
    --target-branch main \
    --dry-run
  ```

## Personalizações sugeridas

- **Novo serviço:** utilize `scripts/bootstrap_instance.sh <app> <instância>` como ponto de partida; em seguida personalize compose, `.env` e documentação antes de prosseguir com validações.
- **Diretórios persistentes:** o caminho `data/<app>-<instância>` é calculado automaticamente; ajuste `APP_DATA_UID` e `APP_DATA_GID` no `.env` correspondente para alinhar permissões ao seu ambiente.
- **Serviços monitorados:** defina `HEALTH_SERVICES` ou `SERVICE_NAME` nos arquivos `.env` para que `scripts/check_health.sh` use os alvos corretos de log.
- **Volumes extras:** utilize overrides específicos (`compose/apps/<app>/<instância>.yml`) para montar diretórios adicionais ou expor portas distintas por ambiente.
- **Overlays por configuração:** registre overlays opcionais em `compose/overlays/*.yml` e habilite-os por ambiente via `COMPOSE_EXTRA_FILES`. Isso mantém diffs de templates restritos a arquivos de configuração, sem editar scripts.

## Fluxos operacionais sugeridos

1. **Deploys regulares:** descreva o passo a passo (pré-validações, comando de deploy, pós-checks) para cada ambiente.
2. **Atualizações:** documente como aplicar upgrades de imagens, dependências ou configurações.
3. **Backups & restores:** integre este guia com [`docs/BACKUP_RESTORE.md`](./BACKUP_RESTORE.md) e detalhe onde os artefatos ficam armazenados.
4. **Troubleshooting:** liste comandos rápidos para coletar logs, métricas ou reiniciar serviços.

Atualize ou substitua seções inteiras conforme necessário para representar fielmente o ciclo de vida operacional do projeto derivado.
