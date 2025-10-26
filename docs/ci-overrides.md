# Diretrizes para sobrescrever testes de CI em projetos derivados

Para manter um fluxo simples de atualização quando este template receber novas
versões, concentre as personalizações de CI nos arquivos indicados abaixo.

## Fluxo recomendado

1. **Não modifique** `.github/workflows/template-quality-checks.yml` nos
   projetos derivados. Esse workflow cobre as verificações básicas fornecidas
   pelo template (lint de shell, validação do Docker Compose e suíte de testes
   principal).
2. Crie ou atualize `.github/workflows/project-tests.yml` no projeto derivado
   para adicionar jobs específicos (por exemplo, lint de código da aplicação,
   smoke tests adicionais ou validações de infraestrutura próprias).
3. Utilize o gatilho `workflow_call` do arquivo `project-tests.yml` para definir
   os jobs necessários. O workflow pai já referencia esse arquivo através de um
   `uses: ./.github/workflows/project-tests.yml`.
4. Quando novas versões do template forem integradas, as personalizações
   permanecerão isoladas no arquivo sobrescrito, reduzindo conflitos de merge.

## Onde criar novos testes

- **Testes Python compartilhados:** continue adicionando no diretório
  `tests/` dentro do template, desde que façam sentido para todos os derivados.
- **Testes específicos do projeto derivado:** mantenha-os fora do template e
  concentre a orquestração no arquivo sobrescrito
  `.github/workflows/project-tests.yml`.

> Dica: ao sobrescrever o workflow, preserve o nome do job principal (por
> exemplo, `project-tests`) para manter a visualização do histórico consistente
> com o template.
