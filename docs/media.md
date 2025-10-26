# Modelo de runbook: ambiente auxiliar

> Utilize este modelo para ambientes de suporte (processamento pesado, staging, laboratório, DR). Ajuste a terminologia para refletir a realidade do seu projeto.

## Contexto do ambiente

- **Objetivo:** descreva o motivo de existir (ex.: workloads assíncronos, testes, integração com parceiros).
- **Restrições:** indique políticas de acesso, limites de recursos ou requisitos de isolamento.
- **Integrações internas:** liste serviços que dependem deste ambiente ou que são consumidos por ele.

## Checklist de deploy

1. Atualize `env/local/<ambiente>.env` com valores específicos (paths, quotas, flags experimentais).
2. Revise a seção [Stacks com múltiplas aplicações](./COMPOSE_GUIDE.md#stacks-com-múltiplas-aplicações) para determinar quais aplicações serão ativadas nesta instância.
3. Valide as combinações de Compose correspondentes (`compose/base.yml`, `compose/apps/<app>/<ambiente>.yml`, etc.).
4. Gere um inventário com `scripts/describe_instance.sh <ambiente>` (guarde o JSON quando quiser alimentar wikis, playbooks automatizados ou painéis de auditoria).
5. Execute o deploy guiado ou comandos equivalentes:
   ```bash
   scripts/deploy_instance.sh <ambiente>
   ```
5. Documente quaisquer passos adicionais (migrações, carregamento de dados de teste, ativação de feature flags).

## Checklist de recuperação

1. Sincronize backups relevantes (dados frios, snapshots, exports de processos automatizados).
2. Execute restore conforme instruções em [`docs/BACKUP_RESTORE.md`](./BACKUP_RESTORE.md), adaptando para os requisitos deste ambiente.
3. Valide integrações dependentes (ex.: filas de processamento, montagens de volume, pipelines de mídia).
4. Informe stakeholders sobre status e diferenças em relação ao ambiente primário.

## Operações específicas

- **Health-checks:** detalhe endpoints, comandos ou dashboards usados para confirmar o estado do ambiente.
- **Tarefas periódicas:** registre rotinas automáticas (limpeza de cache, sincronização de artefatos, upgrades agendados).
- **Experimentos:** se o ambiente suporta features experimentais, documente critérios de entrada/saída e responsáveis.

## Referências

- `compose/base.yml` + `compose/apps/<app>/<ambiente>.yml`
- [Guia de combinações do Docker Compose](./COMPOSE_GUIDE.md#stacks-com-múltiplas-aplicações) para planejar a ativação/desativação de aplicações auxiliares.
- `env/<ambiente>.example.env`
- Scripts adicionais necessários (ex.: seeds de dados, conversores)
- ADRs que justificam a existência deste ambiente
