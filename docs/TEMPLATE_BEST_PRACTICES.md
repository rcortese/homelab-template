# Boas práticas para herdeiros do template

Este guia orienta equipes que criam repositórios derivados a manter consistência com o template original e facilitar atualizações futuras.

## Organização da documentação local

- **Centralize o índice**: atualize `docs/README.md` com links para guias específicos do projeto e mantenha-o genérico.
- **Runbooks atualizados**: mantenha `docs/core.md` e `docs/media.md` (ou equivalentes) alinhados com as operações reais.
- **Histórico de decisões**: registre escolhas arquiteturais em `docs/ADR/`, utilizando a convenção `AAAA-sequência-titulo.md`.
- **Customizações explícitas**: use `docs/local/` para documentar desvios do template (ex.: diretórios adicionais, scripts substituídos) e referencie-os a partir desta página.

## Rastreamento de customizações

1. Liste adaptações relevantes logo após a criação do repositório derivado (ex.: variáveis extras, remoção de scripts, pipelines específicos) no índice de `docs/local/`.
2. Inclua referências cruzadas para PRs, issues e ADRs que justificam cada customização.
3. Atualize o `README.md` do projeto derivado com contexto suficiente para novos contribuidores.

## Mantendo alinhamento com o template

- **Sincronização periódica**: agende revisões (trimestrais ou semestrais) para comparar o repositório derivado com o template.
- **Script de atualização upstream**: utilize `scripts/update_from_template.sh` para reaplicar os commits locais sobre o branch do template. Execute primeiro com `--dry-run`, confirme o remote/commits utilizados e só então aplique a atualização completa.
- **Checklist de atualização**:
  1. Buscar alterações do template (pull/fetch).
  2. Executar o script de merge ou aplicar patches manualmente.
  3. Resolver conflitos mantendo as customizações locais documentadas e priorizando o conteúdo de `docs/local/`.
  4. Rodar validações (`scripts/check_structure.sh`, testes, linters).
  5. Atualizar esta página ou `docs/local/CHANGELOG.md` com a data da sincronização e observações.

## Comunicação e governança

- Defina responsáveis pelo repositório derivado e pela revisão de atualizações upstream.
- Documente canais de comunicação (Slack, e-mail, issues) para tratar dúvidas ou incidentes.
- Incentive PRs que melhorem o template a partir de lições aprendidas nos projetos filhos.

Mantenha este documento visível para novas equipes a fim de promover uma cultura de documentação viva e alinhamento contínuo.
