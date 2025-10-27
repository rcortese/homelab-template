# Modelo de runbook: ambiente primário

> Adapte este documento para representar o ambiente principal do seu serviço (produção, controle, etc.). Use-o como checklist operacional compartilhado entre as equipes.

## Contexto do ambiente

- **Função:** descreva o papel do ambiente (ex.: plano de controle, produção, workload crítico).
- **Dependências externas:** liste serviços, bancos ou integrações obrigatórias.
- **Criticidade:** detalhe objetivos de disponibilidade, RTO/RPO e contatos de escalonamento.

## Checklist de deploy e pós-deploy

Siga o [checklist genérico](./OPERATIONS.md#checklist-generico-deploy-pos) e, para o ambiente primário, complemente com:

- **Preparação reforçada:** gere `scripts/describe_instance.sh <ambiente> --format json` e arquive o relatório no sistema de auditoria antes de iniciar o change.
- **Evidências de execução:** ao aplicar `scripts/deploy_instance.sh <ambiente>`, capture hash de imagens, IDs de pipelines e aprovações formais, anexando-os ao registro de change management.
- **Pós-deploy crítico:** após `scripts/check_health.sh <ambiente>`, valide dashboards de disponibilidade e confirme com o responsável de SRE que alertas prioritários permaneceram estáveis.

> Substitua `<ambiente>` pelo identificador real utilizado no projeto.

## Checklist de recuperação

1. Garanta acesso aos artefatos de backup/documentados em [`docs/BACKUP_RESTORE.md`](./BACKUP_RESTORE.md).
2. Restaure serviços seguindo os comandos oficiais (documente passo a passo aqui).
3. Valide endpoints, filas ou rotinas críticas.
4. Atualize incident tickets com horários, responsáveis e status final.

## Operações recorrentes

- **Verificação de saúde:** descreva comandos/dashboards usados diariamente.
- **Rotinas de limpeza:** defina tarefas programadas (limpeza de logs, rotação de backups, etc.).
- **Auditorias:** liste revisões periódicas (segurança, conformidade, upgrades planejados).

## Referências

- `compose/base.yml` + `compose/apps/<app>/<ambiente>.yml`
- [Guia de combinações do Docker Compose](./COMPOSE_GUIDE.md#stacks-com-múltiplas-aplicações) para orientar a ativação/desativação de aplicações.
- `env/<ambiente>.example.env`
- ADRs relacionados à criação/manutenção deste ambiente
- Scripts personalizados e dashboards principais
