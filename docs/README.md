# Índice da documentação do template

> Use este índice como ponto de partida para personalizar o template. Comece pelo [README principal](../README.md) para entender a proposta geral.

Os documentos abaixo são mantidos genéricos para facilitar merges a partir do template. Para registrar adaptações específicas,
utilize [`docs/local/`](./local/README.md) e apenas referencie esses materiais quando necessário.

## Começando

- [Estrutura do template](./STRUCTURE.md) — Convenções obrigatórias de diretórios, arquivos essenciais e validações.
- [Guia de variáveis de ambiente](../env/README.md) — Como mapear e documentar variáveis em diferentes ambientes.

## Visão geral e integrações

- [Resumo da stack](./OVERVIEW.md) — Personalize este panorama para refletir o contexto do seu fork e mantenha-o atualizado sempre que o repositório derivado divergir do template.
- [Integração de rede](./NETWORKING_INTEGRATION.md) — Ajuste este guia às dependências e requisitos de conectividade específicos, garantindo que forks atualizem essa seção ao evoluir a topologia.

## Operação

- [Operações e scripts padrão](./OPERATIONS.md) — Adapte os utilitários fornecidos para o seu projeto.
- [Combinações de manifests Compose](./COMPOSE_GUIDE.md) — Organize sobreposições e perfis para cenários distintos.
- [Backup & restauração genéricos](./BACKUP_RESTORE.md) — Estratégias de export/import aplicáveis a qualquer stack.

## Runbooks

- [Modelo de runbook primário](./core.md) — Estruture o runbook do ambiente principal do seu serviço.
- [Modelo de runbook auxiliar](./media.md) — Como documentar ambientes de suporte ou workloads especializados.

## Decisões arquiteturais

- [Registro de decisões](./ADR/0001-multi-environment-structure.md) — Exemplo de ADR adaptável para documentar cenários multiambiente.

## Personalizações e manutenção

- [Boas práticas para herdeiros do template](./TEMPLATE_BEST_PRACTICES.md) — Oriente equipes derivadas sobre como manter a documentação e sincronizar atualizações upstream.
- [Apontamentos locais](./local/README.md) — Centralize runbooks, decisões e dependências particulares da sua stack.
