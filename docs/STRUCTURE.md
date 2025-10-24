# Estrutura do template

> Consulte também o [índice geral](./README.md) e ajuste este documento sempre que criar ou remover componentes estruturais.

Este guia descreve a estrutura mínima esperada para qualquer repositório que herde este template. Ele garante que scripts, documentação e pipelines consigam localizar recursos previsivelmente.

## Diretórios obrigatórios

| Caminho | Descrição | Itens esperados |
| --- | --- | --- |
| `compose/` | Manifests Docker Compose base e variações por ambiente ou função. | `base.yml`, sobreposições nomeadas (`<alvo>.yml`). |
| `docs/` | Documentação local, runbooks, guias operacionais e ADRs. | `README.md`, `STRUCTURE.md`, `OPERATIONS.md`, subpastas temáticas e [`local/`](./local/README.md). |
| `env/` | Modelos de variáveis, arquivos de exemplo e orientações de preenchimento. | `*.example.env`, `README.md`, `local/` ignorado no Git. |
| `scripts/` | Automação reutilizável (deploy, validação, backups, health-check). | Scripts shell (ou equivalentes) referenciados pela documentação. |

## Arquivos de referência

| Caminho | Função |
| --- | --- |
| `README.md` | Apresenta o repositório derivado, contexto da stack e links para a documentação local.
| `docs/STRUCTURE.md` | Mantém esta descrição atualizada conforme novos componentes são adicionados.
| `docs/OPERATIONS.md` | Documenta como executar scripts e fluxos operacionais do projeto.
| `docs/ADR/` | Reúne decisões arquiteturais. Cada arquivo deve seguir a convenção `AAAA-sequência-titulo.md`.
| `.github/workflows/` | Pipelines de validação opcionais. Ajuste para refletir verificações e linters do projeto.

## Validações sugeridas

1. **Estrutura** — reutilize `scripts/check_structure.sh` para garantir que diretórios obrigatórios estejam presentes.
2. **Compose** — adapte `scripts/validate_compose.sh` (ou equivalente) para validar manifestos antes de merges/deploys.
3. **Scripts auxiliares** — documente no `README.md` qualquer ferramenta adicional necessária (ex.: `make`, `poetry`, `ansible`).

## Mantendo o template vivo

- Atualize esta página sempre que renomear diretórios ou introduzir novas convenções obrigatórias.
- Revise PRs de projetos derivados para garantir que os diretórios essenciais continuam alinhados ao template.
- Registre desvios intencionais nos ADRs ou no guia de personalização para facilitar auditorias futuras.
