# Operações padrão do template

> Consulte o [índice geral](./README.md) e personalize este guia para refletir a sua stack.

Este documento apresenta um ponto de partida para descrever processos operacionais e o uso dos scripts fornecidos pelo template. Ao derivar um repositório, adapte os exemplos abaixo com comandos concretos do seu serviço.

| Script | Objetivo | Comando básico | Gatilhos recomendados |
| --- | --- | --- | --- |
| [`scripts/check_all.sh`](#scriptscheck_allsh) | Agregar validações de estrutura, `.env` e Compose em um único comando. | `scripts/check_all.sh` | Antes de abrir PRs ou rodar pipelines locais completos. |
| [`scripts/check_structure.sh`](#scriptscheck_structuresh) | Confirmar diretórios/arquivos obrigatórios. | `scripts/check_structure.sh` | Antes de PRs ou pipelines que reorganizam arquivos. |
| [`scripts/check_env_sync.py`](#scriptscheck_env_syncpy) | Verificar sincronização entre Compose e `env/*.example.env`. | `scripts/check_env_sync.py` | Após editar Compose ou templates `.env`; em validações locais/CI. |
| [`scripts/run_quality_checks.sh`](#scriptsrun_quality_checkssh) | Executar `pytest` e `shellcheck` em uma única chamada. | `scripts/run_quality_checks.sh` | Após alterações em código Python ou shell. |
| [`scripts/bootstrap_instance.sh`](#scriptsbootstrap_instancesh) | Criar estrutura inicial de aplicação/instância. | `scripts/bootstrap_instance.sh <app> <instancia>` | Ao iniciar novos serviços ou ambientes. |
| [`scripts/validate_compose.sh`](#scriptsvalidate_composesh) | Validar combinações padrão de Docker Compose. | `scripts/validate_compose.sh` | Após ajustes em manifests; etapas de CI. |
| [`scripts/deploy_instance.sh`](#scriptsdeploy_instancesh) | Orquestrar deploy guiado de instâncias. | `scripts/deploy_instance.sh <alvo>` | Deploys manuais ou automatizados. |
| [`scripts/fix_permission_issues.sh`](#scriptsfix_permission_issuessh) | Ajustar permissões de diretórios persistentes. | `scripts/fix_permission_issues.sh <instancia>` | Antes de subir serviços que usam armazenamento compartilhado. |
| [`scripts/backup.sh`](#scriptsbackupsh) | Gerar snapshot versionado da instância. | `scripts/backup.sh <instancia>` | Rotinas de backup e pré-mudanças invasivas. |
| [`scripts/compose.sh`](#scriptscomposesh) | Padronizar chamadas ao `docker compose`. | `scripts/compose.sh <instancia> <subcomando>` | Operações Compose locais ou em CI. |
| [`scripts/describe_instance.sh`](#scriptsdescribe_instancesh) | Resumir serviços, portas e volumes de uma instância. | `scripts/describe_instance.sh <instancia>` | Auditorias rápidas ou geração de runbooks. |
| [`scripts/check_health.sh`](#scriptscheck_healthsh) | Conferir status dos serviços após mudanças. | `scripts/check_health.sh <instancia>` | Pós-deploy, pós-restore ou troubleshooting. |
| [`scripts/check_db_integrity.sh`](#scriptscheck_db_integritysh) | Validar integridade de bancos SQLite com pausa controlada. | `scripts/check_db_integrity.sh <instancia>` | Manutenções programadas ou investigação de falhas. |
| [`scripts/update_from_template.sh`](#scriptsupdate_from_templatesh) | Reaplicar customizações após atualizar o template. | Consulte o [guia canônico](../README.md#atualizando-a-partir-do-template-original). | Ao sincronizar forks com o upstream. |

## Antes de começar

- Garanta que os arquivos `.env` locais foram gerados a partir dos modelos descritos em [`env/README.md`](../env/README.md).
- Revise as combinações de manifests (`compose/base.yml` + overrides) que serão utilizadas pelos scripts.
- Execute `scripts/check_all.sh` para validar estrutura, sincronização de variáveis e manifests Compose antes de abrir PRs ou publicar mudanças locais.
- Execute `scripts/check_env_sync.py` isoladamente sempre que editar manifests ou templates `.env` para garantir que as variáveis continuam sincronizadas.
- Documente dependências extras (CLI, credenciais, acesso a registries) em seções adicionais.

<a id="checklist-generico-deploy-pos"></a>
## Checklist genérico de deploy e pós-deploy

> Utilize este checklist como base comum para todos os ambientes derivados deste template.

### Preparação

1. Atualize `env/local/<instancia>.env` com as variáveis mais recentes antes de gerar ou aplicar manifests.
2. Revise a seção [Stacks com múltiplas aplicações](./COMPOSE_GUIDE.md#stacks-com-múltiplas-aplicações) para confirmar quais serviços devem ser ativados ou desativados no ciclo atual.
3. Valide os manifests com `scripts/validate_compose.sh` (ou comando equivalente) para garantir que a combinação de arquivos continua consistente.
4. Gere um resumo com `scripts/describe_instance.sh <instancia>`; quando precisar de trilha de auditoria ou material de apoio, salve também a saída `--format json` junto ao checklist do deploy.

### Execução

1. Rode o fluxo guiado de deploy:
   ```bash
   scripts/deploy_instance.sh <instancia>
   ```
2. Registre outputs relevantes (hash de imagens utilizadas, versão de pipelines ou artefatos aplicados) para referência posterior.

### Pós-deploy

1. Execute `scripts/check_health.sh <instancia>` — ou verificação equivalente — para validar o estado dos serviços recém-publicados.
2. Revise dashboards, alertas críticos e integrações que dependem da instância, garantindo que métricas e notificações retornaram ao comportamento esperado.

### Configurando a rede interna compartilhada

- Utilize os placeholders definidos em `env/common.example.env` para nome, driver, sub-rede e gateway da rede (`APP_NETWORK_NAME`, `APP_NETWORK_DRIVER`, `APP_NETWORK_SUBNET`, `APP_NETWORK_GATEWAY`). Ajuste-os conforme a topologia do seu ambiente antes de gerar os arquivos reais em `env/local/`.
- Cada instância deve reservar endereços IPv4 exclusivos para os serviços. Os modelos `env/core.example.env` e `env/media.example.env` ilustram como separar os IPs do serviço `app` (`APP_NETWORK_IPV4`), do serviço `monitoring` (`MONITORING_NETWORK_IPV4`) e do serviço `worker` (`WORKER_CORE_NETWORK_IPV4` e `WORKER_MEDIA_NETWORK_IPV4`).
- Ao criar novas instâncias ou serviços adicionais, replique o padrão: declare variáveis `*_NETWORK_IPV4` específicas no template `.env` correspondente e conecte o serviço à rede `homelab_internal` (ou ao nome definido em `APP_NETWORK_NAME`) dentro do manifest Compose.
- Depois de ajustar os IPs, execute `scripts/validate_compose.sh` ou `docker compose config -q` para validar se não há sobreposições ou lacunas na configuração.

## scripts/check_all.sh

- **Ordem das verificações:**
  1. `scripts/check_structure.sh` — garante que diretórios e arquivos obrigatórios estão presentes.
  2. `scripts/check_env_sync.py` — valida a sincronização entre os manifests Compose e os arquivos `env/*.example.env`.
  3. `scripts/validate_compose.sh` — confirma se as combinações de Compose permanecem válidas para os perfis suportados.
- **Comportamento em caso de falha:** o script é executado com `set -euo pipefail` e encerra imediatamente na primeira verificação que retornar código diferente de zero, propagando a mensagem do helper que falhou.
- **Variáveis e flags relevantes:** não possui parâmetros próprios; respeita as variáveis aceitas pelos scripts internos (`COMPOSE_INSTANCES`, `COMPOSE_EXTRA_FILES`, `DOCKER_COMPOSE_BIN`, entre outras). Exporte-as antes da chamada quando precisar personalizar o encadeamento.
- **Orientações de uso:** priorize `scripts/check_all.sh` em ciclos de validação completos antes de abrir PRs, sincronizar forks ou iniciar pipelines manuais. Utilize os scripts individuais apenas durante ajustes focados (por exemplo, rodar `scripts/check_env_sync.py` após editar um `.env`). Reproduza a chamada em pipelines de CI que representem o fluxo local de validações, mantendo paridade entre ambientes.

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

## scripts/run_quality_checks.sh

- **Objetivo:** concentrar a suíte base de qualidade (`python -m pytest` e `shellcheck` nos scripts do repositório) em um único comando.
- **Uso típico:**
  ```bash
  scripts/run_quality_checks.sh
  scripts/run_quality_checks.sh --no-lint
  ```
- **Personalização:** defina `PYTHON_BIN` ou `SHELLCHECK_BIN` para apontar binários alternativos quando necessário (por exemplo, em ambientes virtuais ou wrappers locais) ou passe `--no-lint` quando quiser apenas rodar a suíte de testes Python.
- **Boas práticas:** execute o helper durante ciclos iterativos em código Python ou shell para detectar regressões rapidamente e replique a chamada em pipelines locais antes de rodar `scripts/check_all.sh`.

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

  > Diretórios de aplicações que fornecem apenas overrides (`compose/apps/<app>/<instância>.yml`) são aceitos. O helper de
  > planejamento ignora automaticamente `compose/apps/<app>/base.yml` quando o arquivo não existir, mantendo a lista de `-f`
  > consistente com os manifests disponíveis.

  > As variáveis podem ser exportadas previamente (`export COMPOSE_INSTANCES=...`) ou prefixadas ao comando, mantendo o fluxo simples.
  > **Alerta:** use a validação para confirmar se as combinações padrão de Compose permanecem compatíveis com os perfis ativos antes de implantações ou PRs.

## scripts/deploy_instance.sh

Além das flags principais (`--force`, `--skip-structure`, `--skip-validate`, `--skip-health`), personalize prompts e combinações de arquivos para refletir ambientes reais. Defina `COMPOSE_EXTRA_FILES` no `.env` quando precisar de overlays adicionais. O script calcula o diretório persistente a partir de `APP_DATA_DIR` (caminho relativo) ou `APP_DATA_DIR_MOUNT` (caminho absoluto) — deixe ambos vazios para usar o fallback `data/<app>-<instância>` e nunca habilite as duas variáveis ao mesmo tempo, pois a rotina aborta com erro.

## scripts/fix_permission_issues.sh

O script depende de `scripts/lib/deploy_context.sh` para calcular `APP_DATA_DIR` ou `APP_DATA_DIR_MOUNT`, além de `APP_DATA_UID` e `APP_DATA_GID`. Em ambientes compartilhados, combine a execução com `--dry-run` para revisar alterações antes de aplicar `chown`. Documente exceções ao padrão relativo `data/<app>-<instância>` e lembre-se de que apenas uma das variáveis (`APP_DATA_DIR` ou `APP_DATA_DIR_MOUNT`) pode estar definida.

## scripts/backup.sh

- **Dependências:**
  - o `.env` da instância deve estar atualizado para que `scripts/lib/deploy_context.sh` identifique `APP_DATA_DIR`, `COMPOSE_FILES` e demais variáveis utilizadas na montagem da stack;
  - o diretório `backups/` precisa estar acessível para gravação (o script cria subpastas automaticamente, mas respeita permissões do host);
  - recomenda-se garantir que o `.env` esteja carregado (`source env/<instancia>.env`) quando houver exports adicionais exigidos pelos serviços.
- O comando padrão (`scripts/backup.sh core`) gera um snapshot completo da instância e informa o local do artefato ao final. Consulte [`docs/BACKUP_RESTORE.md`](./BACKUP_RESTORE.md) para práticas de retenção e restauração.
- **Dicas de personalização para forks:**
  - Exporte variáveis complementares (por exemplo, `EXTRA_BACKUP_PATHS` ou credenciais de repositórios externos) antes de chamar o script, permitindo que wrappers locais incluam diretórios extras ou enviem os artefatos para armazenamento remoto.
  - Ajuste o `.env` da instância para apontar `APP_DATA_DIR` (relativo) ou `APP_DATA_DIR_MOUNT` (absoluto) quando o layout de dados divergir do padrão `data/<app>-<instância>` — nunca habilite os dois ao mesmo tempo.
  - Amplie o fluxo em wrappers externos adicionando hooks pré/pós-backup (scripts auxiliares, notificações ou compressão) mantendo a lógica central de parada/cópia/restart encapsulada aqui.

## scripts/compose.sh

- **Formato básico:** `scripts/compose.sh <instancia> <subcomando> [argumentos...]`. A instância define quais manifests (`compose/base.yml`, overlays de app e overrides da instância) e cadeias de `.env` serão carregados antes de encaminhar o subcomando ao `docker compose`.
- **Sem instância:** utilize `--` para separar os argumentos quando quiser apenas reutilizar o wrapper sem carregar metadados (ex.: `scripts/compose.sh -- config`).
- **Variáveis úteis:** `DOCKER_COMPOSE_BIN` sobrescreve o binário invocado; `COMPOSE_FILES` e `COMPOSE_ENV_FILE` (ou `COMPOSE_ENV_FILES`) forçam combinações personalizadas sem depender dos manifests/`.env` padrão; `APP_DATA_DIR` (relativo) e `APP_DATA_DIR_MOUNT` (absoluto) são opcionais e devem ser usados de forma exclusiva — deixe ambos vazios para adotar o fallback `data/<app>-<instância>` calculado automaticamente.
- **Ajuda integrada:** `scripts/compose.sh --help` descreve todas as opções suportadas e exemplos adicionais (`scripts/compose.sh core up -d`, `scripts/compose.sh media logs app`, `scripts/compose.sh core -- down app`).

## scripts/describe_instance.sh

- **Descobrir instâncias disponíveis:** execute `scripts/describe_instance.sh --list` para validar quais combinações o template expõe antes de solicitar um resumo específico.
- **Formatações disponíveis:**
  - `table` (padrão) — ideal para revisões rápidas em terminais ou runbooks.
  - `json` — voltado para integrações automatizadas e geração de documentação.
- A saída em `table` facilita revisões rápidas. Com `--format json`, campos como `compose_files`, `extra_overlays` e `services` podem alimentar geradores de runbooks ou páginas de status.
- Destaque: o relatório aponta overlays adicionais vindos de `COMPOSE_EXTRA_FILES`, facilitando auditorias sobre customizações temporárias.

## scripts/check_health.sh

- **Argumentos e variáveis suportadas:**
  - `HEALTH_SERVICES` — lista de serviços a inspecionar (separada por espaços ou vírgulas). Quando definido, limita a execução apenas aos serviços desejados.
  - `COMPOSE_ENV_FILE` — caminho para um arquivo `.env` alternativo a ser carregado antes de consultar o `docker compose`.
- O script complementa automaticamente a lista de serviços executando `docker compose config --services`. Caso nenhum serviço seja encontrado, a execução aborta com erro para evitar supressão silenciosa de logs.
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

Este documento mantém apenas um resumo: utilize `scripts/update_from_template.sh` para reaplicar customizações
após sincronizar o fork com o template. Para o passo a passo detalhado, parâmetros explicados e exemplos de
execução, consulte a seção ["Atualizando a partir do template original"](../README.md#atualizando-a-partir-do-template-original)
no `README.md`, que é a fonte única de verdade para esse fluxo. Registre aqui apenas adaptações locais que não
entrem em conflito com o guia principal.

## Personalizações sugeridas

- **Novo serviço:** utilize `scripts/bootstrap_instance.sh <app> <instância>` como ponto de partida; em seguida personalize compose, `.env` e documentação antes de prosseguir com validações.
- **Diretórios persistentes:** o caminho `data/<app>-<instância>` é calculado automaticamente; utilize `APP_DATA_DIR` (relativo) **ou** `APP_DATA_DIR_MOUNT` (absoluto) quando precisar personalizar o destino e ajuste `APP_DATA_UID`/`APP_DATA_GID` no `.env` para alinhar permissões.
- **Serviços monitorados:** defina `HEALTH_SERVICES` nos arquivos `.env` para que `scripts/check_health.sh` use os alvos corretos de log.
- **Volumes extras:** utilize overrides específicos (`compose/apps/<app>/<instância>.yml`) para montar diretórios adicionais ou expor portas distintas por ambiente.
- **Overlays por configuração:** registre overlays opcionais em `compose/overlays/*.yml` e habilite-os por ambiente via `COMPOSE_EXTRA_FILES`. Isso mantém diffs de templates restritos a arquivos de configuração, sem editar scripts.

## Fluxos operacionais sugeridos

1. **Deploys regulares:** descreva o passo a passo (pré-validações, comando de deploy, pós-checks) para cada ambiente.
2. **Atualizações:** documente como aplicar upgrades de imagens, dependências ou configurações.
3. **Backups & restores:** integre este guia com [`docs/BACKUP_RESTORE.md`](./BACKUP_RESTORE.md) e detalhe onde os artefatos ficam armazenados.
4. **Troubleshooting:** liste comandos rápidos para coletar logs, métricas ou reiniciar serviços.

Atualize ou substitua seções inteiras conforme necessário para representar fielmente o ciclo de vida operacional do projeto derivado.
