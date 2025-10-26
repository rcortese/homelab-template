# Operações padrão do template

> Consulte o [índice geral](./README.md) e personalize este guia para refletir a sua stack.

Este documento apresenta um ponto de partida para descrever processos operacionais e o uso dos scripts fornecidos pelo template. Ao derivar um repositório, adapte os exemplos abaixo com comandos concretos do seu serviço.

## Antes de começar

- Garanta que os arquivos `.env` locais foram gerados a partir dos modelos descritos em [`env/README.md`](../env/README.md).
- Revise as combinações de manifests (`compose/base.yml` + overrides) que serão utilizadas pelos scripts.
- Documente dependências extras (CLI, credenciais, acesso a registries) em seções adicionais.

## scripts/check_structure.sh

- **Objetivo:** validar se diretórios e arquivos obrigatórios definidos em `docs/STRUCTURE.md` estão presentes.
- **Uso típico:**
  ```bash
  scripts/check_structure.sh
  ```
- **Quando executar:** antes de abrir PRs que reorganizam arquivos ou em pipelines de CI.

<a id="scriptsvalidate_compose.sh"></a>
## scripts/validate_compose.sh

- **Objetivo:** verificar se as combinações padrão de Docker Compose continuam válidas.
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

## scripts/deploy_instance.sh

- **Objetivo:** oferecer um fluxo guiado de deploy reutilizando as validações do template.
- **Personalização sugerida:** ajuste as combinações de arquivos e os prompts para refletir ambientes reais (produção, staging, laboratório, etc.).
- **Uso genérico:**
  ```bash
  scripts/deploy_instance.sh <alvo>
  scripts/deploy_instance.sh <alvo> --dry-run
  ```
- **Flags principais:** `--force`, `--skip-structure`, `--skip-validate`, `--skip-health`.
- **Dica:** defina `COMPOSE_EXTRA_FILES` no `.env` da instância para incluir overlays específicos (ex.: `compose/overlays/observability.yml`).

## scripts/fix_permission_issues.sh

- **Objetivo:** normalizar permissões de diretórios persistentes definidos na instância antes de executar serviços Docker.
- **Contexto:** lê os valores calculados por `scripts/lib/deploy_context.sh`, utilizando `APP_DATA_DIR`, `APP_DATA_UID` e `APP_DATA_GID` definidos no `.env` da instância (ou valores padrão `data/<app>-<instância>` e `1000:1000`).
- **Uso típico:**
  ```bash
  scripts/fix_permission_issues.sh <instancia>
  scripts/fix_permission_issues.sh <instancia> --dry-run
  ```
- **Comportamento:**
  - garante que os diretórios de dados e `backups/` existam (`mkdir -p`);
  - aplica `chown <uid>:<gid>` quando executado com privilégios suficientes;
  - valida o owner final e emite avisos se persistirem divergências.
- **Boas práticas:** siga a convenção `data/<app>-<instância>` sempre que possível para manter a organização padrão. Sobrescreva `APP_DATA_DIR` apenas quando precisar apontar para armazenamento alternativo (por exemplo, volumes montados no host, dispositivos dedicados ou diretórios com requisitos especiais) e documente o `UID:GID` esperado para evitar conflitos em ambientes multiusuário.

## scripts/compose.sh

- **Objetivo:** encapsular chamadas ao `docker compose` utilizando convenções do template.
- **Boas práticas:**
  - Defina `COMPOSE_FILES` e `COMPOSE_ENV_FILE` quando precisar de combinações personalizadas.
  - Registre exemplos específicos da sua stack nesta seção.

## scripts/check_health.sh

- **Objetivo:** consultar status de serviços após deploys, restores ou troubleshooting.
- **Adaptação necessária:** documente quais endpoints, comandos ou logs devem ser verificados para cada ambiente.
- **Argumentos e variáveis suportadas:**
  - `HEALTH_SERVICES` — lista de serviços a inspecionar (separada por espaços ou vírgulas). Quando definido, limita a execução apenas aos serviços desejados.
  - `SERVICE_NAME` — nome de um serviço específico para reduzir o escopo (útil ao investigar incidentes pontuais).
  - `COMPOSE_ENV_FILE` — caminho para um arquivo `.env` alternativo a ser carregado antes de consultar o `docker compose`.
- **Notas importantes:** o script complementa automaticamente a lista de serviços ao executar `docker compose config --services`, garantindo que as instâncias definidas nos manifests estejam sempre cobertas mesmo quando `HEALTH_SERVICES` não estiver configurado.
- **Exemplos práticos:**
  ```bash
  # Execução padrão usando os manifests configurados na instância
  scripts/check_health.sh core

  # Filtra apenas serviços explícitos (separação por vírgulas ou espaços)
  HEALTH_SERVICES="frontend,worker" scripts/check_health.sh core
  ```

## scripts/check_db_integrity.sh

- **Objetivo:** suspender temporariamente os serviços ativos da instância e validar a integridade de bancos SQLite armazenados em `data/` (ou em um diretório customizado).
- **Parâmetros úteis:**
  - `--data-dir` — diretório raiz onde os arquivos `.db` serão buscados.
  - `--no-resume` — evita retomar automaticamente os serviços ao final da verificação (útil em investigações manuais).
  - `SQLITE3_MODE` — define o backend (`container`, `binary` ou `auto`; padrão `container`).
  - `SQLITE3_CONTAINER_RUNTIME` — runtime utilizado para executar o contêiner (padrão `docker`).
  - `SQLITE3_CONTAINER_IMAGE` — imagem utilizada para o comando `sqlite3` (padrão `keinos/sqlite3:latest`).
  - `SQLITE3_BIN` — caminho para um binário local usado em modo `binary` ou como fallback.
- **Fluxo padrão:**
  ```bash
  scripts/check_db_integrity.sh core
  ```
- **Observações operacionais:**
  - Backups com sufixo `.bak` são gerados automaticamente antes de sobrescrever um banco recuperado.
  - Sempre que uma inconsistência é detectada (mesmo após recuperação), alertas são emitidos na saída de erro padrão para facilitar integrações com sistemas de monitoramento.
  - Combine com janelas de manutenção curtas, pois os serviços permanecem pausados durante toda a inspeção.

## scripts/update_from_template.sh

- **Objetivo:** re-aplicar personalizações locais sobre a versão mais recente do template oficial usando `git rebase --onto`.
- **Parâmetros principais:**
  - `--remote` — nome do remote que aponta para o repositório original do template.
  - `--original-commit` — hash do commit do template usado quando o fork foi criado.
  - `--first-local-commit` — hash do primeiro commit exclusivo do repositório derivado.
  - `--dry-run` — executa apenas a simulação do rebase sem alterar a branch atual.
- **Referência adicional:** consulte a seção ["Atualizando a partir do template original"](../README.md#atualizando-a-partir-do-template-original) do `README.md` para o passo a passo completo.
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
