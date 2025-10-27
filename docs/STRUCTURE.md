# Estrutura do template

> Consulte também o [índice geral](./README.md) e ajuste este documento sempre que criar ou remover componentes estruturais.

Este guia descreve a estrutura mínima esperada para qualquer repositório que herde este template. Ele garante que scripts, documentação e pipelines consigam localizar recursos previsivelmente.

## Diretórios obrigatórios

> Fonte única de verdade para os diretórios mínimos exigidos pelo template. Sempre atualize esta tabela antes de replicar mudanças em outros documentos.

| Caminho | Descrição | Itens esperados |
| --- | --- | --- |
| `compose/` | Manifests Docker Compose base e variações por ambiente ou função. | `base.yml`, sobreposições nomeadas (`<alvo>.yml`, ex.: [`core.yml`](../compose/core.yml) e [`media.yml`](../compose/media.yml)) e diretórios em `compose/apps/`. |
| `docs/` | Documentação local, runbooks, guias operacionais e ADRs. | `README.md`, `STRUCTURE.md`, `OPERATIONS.md`, subpastas temáticas e [`local/`](./local/README.md). |
| `env/` | Modelos de variáveis, arquivos de exemplo e orientações de preenchimento. | `*.example.env`, `README.md`, `local/` ignorado no Git. Expanda com variáveis necessárias para todas as aplicações ativadas. |
| `scripts/` | Automação reutilizável (deploy, validação, backups, health-check). | Scripts shell (ou equivalentes) referenciados pela documentação. |
| `tests/` | Verificações automatizadas do template que devem ser preservadas nos forks. | Testes base do template; cenários específicos podem viver em diretórios próprios fora de `tests/`, conforme indicado em [`tests/README.md`](../tests/README.md). |
| `.github/workflows/` | Pipelines de CI que garantem a qualidade mínima do template. | `template-quality.yml` (mantido conforme o template) e workflows adicionais necessários para a stack derivada. |

> Os utilitários `scripts/check_structure.sh` e a suíte `tests/test_check_structure.py` verificam explicitamente a presença desse diretório e do arquivo `template-quality.yml`. Se qualquer item faltar, o fluxo automático falha.

## Arquivos de referência

| Caminho | Função |
| --- | --- |
| `README.md` | Apresenta o repositório derivado, contexto da stack e links para a documentação local.
| `docs/STRUCTURE.md` | Mantém esta descrição atualizada conforme novos componentes são adicionados.
| `docs/OPERATIONS.md` | Documenta como executar scripts e fluxos operacionais do projeto.
| `docs/ADR/` | Reúne decisões arquiteturais. Cada arquivo deve seguir a convenção `AAAA-sequência-titulo.md`.

## Componentes por aplicação

Cada aplicação adicional precisa seguir o padrão abaixo para manter a compatibilidade com os scripts e runbooks do template:

> Dica: utilize `scripts/bootstrap_instance.sh <app> <instância>` para gerar automaticamente os arquivos listados na tabela abaixo antes de personalizá-los. Para aplicações compostas apenas por overrides, adicione `--override-only` ou deixe o script detectar diretórios existentes sem `base.yml`.

| Caminho | Obrigatório? | Descrição |
| --- | --- | --- |
| `compose/apps/<app>/` | Sim | Diretório próprio com manifests da aplicação. |
| `compose/apps/<app>/base.yml` | Quando aplicável | Serviços base reutilizáveis por todas as instâncias. Opcional para aplicações compostas apenas por overrides específicos de instância. |
| `compose/apps/<app>/<instância>.yml` | Um por instância | Override com nomes de serviços, portas e variáveis específicas. |
| `docs/apps/<app>.md` | Recomendado | Documento de apoio descrevendo responsabilidades e requisitos da aplicação. |
| `env/<instância>.example.env` | Um por instância | Deve incluir todas as variáveis consumidas pelos manifests das aplicações habilitadas para a instância. |

> Para aplicações compostas apenas por overrides, garanta a presença dos arquivos `<instância>.yml` e siga as orientações detalhadas em [Aplicações override-only](./COMPOSE_GUIDE.md#aplicações-compostas-apenas-por-overrides).

## Validações sugeridas

1. **Estrutura** — reutilize `scripts/check_structure.sh` para garantir que diretórios obrigatórios estejam presentes.
2. **Compose** — adapte `scripts/validate_compose.sh` (ou equivalente) para validar manifestos antes de merges/deploys.
3. **Scripts auxiliares** — documente no `README.md` qualquer ferramenta adicional necessária (ex.: `make`, `poetry`, `ansible`).

## Mantendo o template vivo

- Atualize esta página sempre que renomear diretórios ou introduzir novas convenções obrigatórias.
- Revise PRs de projetos derivados para garantir que os diretórios essenciais continuam alinhados ao template.
- Registre desvios intencionais nos ADRs ou no guia de personalização para facilitar auditorias futuras.
