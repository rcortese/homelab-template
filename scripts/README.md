# Guia rápido dos scripts de automação

Este diretório concentra os entrypoints usados no dia a dia para validar, implantar e manter stacks derivadas do template. As seções abaixo agrupam os helpers por categoria, resumem o objetivo de cada script e apontam para descrições detalhadas em [`docs/OPERATIONS.md`](../docs/OPERATIONS.md).

## Entrypoints na raiz vs utilitários em `lib/`

Os arquivos em `scripts/*.sh` e `scripts/*.py` são entrypoints prontos para execução direta via CLI (`scripts/<nome>.sh`). Eles carregam funções auxiliares a partir de `scripts/lib/` utilizando `source "$SCRIPT_DIR/lib/<arquivo>.sh"` (para shell) ou os módulos Python equivalentes quando necessário. O padrão `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` garante que cada entrypoint encontre os utilitários relativos ao repositório, mantendo o comportamento consistente mesmo fora da raiz do projeto.

Os utilitários presentes em `scripts/lib/` nunca são executados isoladamente: eles expõem funções reutilizáveis (por exemplo, composição de manifests, carregamento de `.env`, execução de etapas) que são importadas pelos entrypoints. Ao criar novos scripts, reutilize essas bibliotecas para evitar duplicação e preservar os fluxos já documentados.

## Convenções de uso

- **Shell resiliente:** todos os scripts Bash adotam `set -euo pipefail` para abortar em falhas e prevenir variáveis não declaradas. Preserve essa configuração ao escrever novos helpers.
- **Variáveis de ambiente compartilhadas:** helpers aceitam variáveis como `COMPOSE_INSTANCES`, `COMPOSE_EXTRA_FILES`, `DOCKER_COMPOSE_BIN`, `APP_DATA_DIR`, `APP_DATA_DIR_MOUNT`, `APP_DATA_UID`/`APP_DATA_GID`, entre outras. Consulte cada seção em [`docs/OPERATIONS.md`](../docs/OPERATIONS.md) para detalhes e exporte-as antes da execução quando precisar personalizar o comportamento.
- **Dependências externas:** certifique-se de ter Docker Compose v2 disponível (`docker compose ...`) e as ferramentas usadas pelos linters (por exemplo, `shfmt`, `shellcheck`, `checkbashisms`). Os trechos em Python são executados via imagem oficial (`python:3.11-slim`) quando o Docker está presente; o runtime local de Python 3 é usado apenas como fallback e instala automaticamente as dependências de `requirements-dev.txt` se necessário. Alguns fluxos utilizam também `git`, `tar`, `jq` e utilitários padrão do GNU coreutils.

## Catálogo por categoria

### Validações

| Script | Resumo | Referência |
| --- | --- | --- |
| `check_all.sh` | Encadeia estrutura, sincronização de variáveis e validação Compose em uma única chamada antes de PRs. | [`docs/OPERATIONS.md#scriptscheck_allsh`](../docs/OPERATIONS.md#scriptscheck_allsh) |
| `check_structure.sh` | Garante que diretórios e arquivos mandatórios do template estejam presentes. | [`docs/OPERATIONS.md#scriptscheck_structuresh`](../docs/OPERATIONS.md#scriptscheck_structuresh) |
| `check_env_sync.sh` | Compara manifests Compose com `env/*.example.env`, sinalizando variáveis ausentes ou obsoletas. | [`docs/OPERATIONS.md#scriptscheck_env_syncpy`](../docs/OPERATIONS.md#scriptscheck_env_syncpy) |
| `run_quality_checks.sh` | Reúne `pytest`, `shfmt`, `shellcheck` e `checkbashisms` para validações de qualidade. | [`docs/OPERATIONS.md#scriptsrun_quality_checkssh`](../docs/OPERATIONS.md#scriptsrun_quality_checkssh) |
| `validate_compose.sh` | Valida combinações padrão de Docker Compose para diferentes perfis/instâncias. | [`docs/OPERATIONS.md#scriptsvalidate_composesh`](../docs/OPERATIONS.md#scriptsvalidate_composesh) |

### Orquestração de deploy

| Script | Resumo | Referência |
| --- | --- | --- |
| `deploy_instance.sh` | Executa o fluxo guiado de deploy (planos, validações, `docker compose up`, health check). | [`docs/OPERATIONS.md#scriptsdeploy_instancesh`](../docs/OPERATIONS.md#scriptsdeploy_instancesh) |
| `compose.sh` | Padroniza chamadas ao `docker compose` usando os manifests e variáveis do template. | [`docs/OPERATIONS.md#scriptscomposesh`](../docs/OPERATIONS.md#scriptscomposesh) |
| `bootstrap_instance.sh` | Gera a estrutura inicial de aplicações/instâncias, com suporte a overrides e documentação. | [`docs/OPERATIONS.md#scriptsbootstrap_instancesh`](../docs/OPERATIONS.md#scriptsbootstrap_instancesh) |

### Manutenção

| Script | Resumo | Referência |
| --- | --- | --- |
| `fix_permission_issues.sh` | Ajusta permissões de diretórios persistentes usando o contexto calculado da instância. | [`docs/OPERATIONS.md#scriptsfix_permission_issuessh`](../docs/OPERATIONS.md#scriptsfix_permission_issuessh) |
| `backup.sh` | Cria snapshots versionados dos dados da instância e registra o local do artefato. | [`docs/OPERATIONS.md#scriptsbackupsh`](../docs/OPERATIONS.md#scriptsbackupsh) |
| `update_from_template.sh` | Reaplica customizações após sincronizar o fork com o template original. | [`docs/OPERATIONS.md#scriptsupdate_from_templatesh`](../docs/OPERATIONS.md#scriptsupdate_from_templatesh) |
| `detect_template_commits.sh` | Identifica o commit base do template e o primeiro commit exclusivo do fork. | [`docs/OPERATIONS.md#scriptsdetect_template_commitssh`](../docs/OPERATIONS.md#scriptsdetect_template_commitssh) |

### Diagnóstico

| Script | Resumo | Referência |
| --- | --- | --- |
| `describe_instance.sh` | Resume serviços, portas e volumes de uma instância (inclui modo `--format json`). | [`docs/OPERATIONS.md#scriptsdescribe_instancesh`](../docs/OPERATIONS.md#scriptsdescribe_instancesh) |
| `check_health.sh` | Executa verificações pós-deploy para confirmar o status dos serviços ativos. | [`docs/OPERATIONS.md#scriptscheck_healthsh`](../docs/OPERATIONS.md#scriptscheck_healthsh) |
| `check_db_integrity.sh` | Realiza inspeções em bancos SQLite com pausa controlada das aplicações envolvidas. | [`docs/OPERATIONS.md#scriptscheck_db_integritysh`](../docs/OPERATIONS.md#scriptscheck_db_integritysh) |

> Para scripts adicionais (por exemplo, wrappers em `scripts/local/` ou modelos em `scripts/templates/`), replique estas convenções ao documentar extensões específicas do seu fork.
