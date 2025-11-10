# Modelo de runbook: ambiente auxiliar

> Utilize este modelo para ambientes de suporte (processamento pesado, staging, laboratório, DR). Ajuste a terminologia para refletir a realidade do seu projeto.

## Contexto do ambiente

- **Objetivo:** descreva o motivo de existir (ex.: workloads assíncronos, testes, integração com parceiros).
- **Restrições:** indique políticas de acesso, limites de recursos ou requisitos de isolamento.
- **Integrações internas:** liste serviços que dependem deste ambiente ou que são consumidos por ele.

## Checklist de deploy e pós-deploy

Siga o [checklist genérico](./OPERATIONS.md#checklist-generico-deploy-pos) e, para o ambiente auxiliar, complemente com:

- **Preparação contextualizada:** ao atualizar `env/local/<ambiente>.env`, registre quotas, flags experimentais e limites que diferem do ambiente primário para manter a rastreabilidade de testes e workloads pesados.
- **Documentação adicional:** depois de `scripts/deploy_instance.sh <ambiente>`, liste migrações, cargas de dados de teste ou feature flags ativadas para facilitar reproduções futuras.
- **Pós-deploy focalizado:** além de `scripts/check_health.sh <ambiente>`, valide filas de processamento, montagens de mídia e integrações consumidas por times parceiros, atualizando o canal de comunicação combinado (ex.: Slack, wiki ou planilha de ensaios).

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

- (`compose/base.yml`, quando existir) + (`compose/<ambiente>.yml`, quando existir) + `compose/apps/<app>/<ambiente>.yml`
- [Guia de combinações do Docker Compose](./COMPOSE_GUIDE.md#stacks-com-múltiplas-aplicações) para planejar a ativação/desativação de aplicações auxiliares.
- `env/<ambiente>.example.env`
- Scripts adicionais necessários (ex.: seeds de dados, conversores)
- ADRs que justificam a existência deste ambiente
