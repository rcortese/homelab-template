# ADR 0001 — Estrutura multiambiente para serviços derivados

## Status

Aceito

## Contexto

Ao reutilizar este template, é comum dividir responsabilidades em múltiplos ambientes (por exemplo: produção vs. processamento pesado, controle vs. laboratório). Precisamos de uma convenção inicial que sirva de referência para documentar essas divisões e orientar scripts/runbooks.

## Decisão

- Manter pelo menos dois ambientes nomeados (`<ambiente-primario>` e `<ambiente-auxiliar>`) ao iniciar um projeto derivado.
- Registrar runbooks separados em `docs/core.md` e `docs/media.md` (ou renomeações equivalentes) contendo checklists de deploy, recuperação e operações recorrentes.
- Definir variáveis de ambiente e manifests específicos para cada ambiente, mantendo os modelos em `env/` e `compose/`.
- Documentar dependências externas compartilhadas em [`docs/NETWORKING_INTEGRATION.md`](../NETWORKING_INTEGRATION.md), garantindo que impactos sejam mapeados por ambiente.

## Consequências

- Projetos derivados possuem um ponto de partida claro para separar cargas de trabalho, o que facilita escalabilidade e isolamento.
- Scripts e validações do template podem ser reutilizados sem alterações profundas, bastando informar o nome do ambiente desejado.
- Caso um projeto precise de apenas um ambiente, a equipe deve registrar um novo ADR explicando a alteração e atualizar a documentação correspondente.
