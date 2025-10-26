# Homelab service template

Este repositório serve como **template reutilizável** para stacks autocontidas. Ele reúne infraestrutura como código, scripts de operação e documentação sob uma mesma convenção para facilitar forks ou projetos derivados.

Para uma visão completa da documentação utilize o [índice em `docs/README.md`](docs/README.md).

Mantemos este arquivo genérico para facilitar a sincronização com novas versões do template. Informações específicas da sua
stack devem ser descritas nos apontamentos locais indicados em [Customização local](#customização-local).

## Pré-requisitos

Certifique-se de ter as ferramentas abaixo instaladas e atualizadas antes de trabalhar em um fork deste template:

- Docker Engine
- Docker Compose v2
- Python 3.x
- ShellCheck, shfmt ou ferramentas equivalentes para lint/format de shell scripts

### Checklist rápido

Os scripts abaixo pressupõem que os arquivos `.env` locais já estejam configurados.

1. Copie os modelos de `env/*.example.env` para `env/local/` seguindo o passo a passo em [`env/README.md`](env/README.md).
2. Valide a sincronização das variáveis com os manifests executando `scripts/check_env_sync.py`.
3. Em seguida, execute:

   ```bash
   pip install -r requirements-dev.txt
   scripts/check_structure.sh
   scripts/validate_compose.sh
   ```

> Quando criar um guia de onboarding específico da stack, replique esta sequência para manter as instruções alinhadas entre os documentos.

## Conteúdo obrigatório

Os diretórios abaixo devem existir em qualquer repositório filho criado a partir deste template:

| Caminho | Finalidade |
| --- | --- |
| `compose/` | Manifests Docker Compose base e sobreposições por ambiente/alvo.
| `docs/` | Guias operacionais, runbooks e decisões arquiteturais alinhados à stack.
| `env/` | Modelos de variáveis de ambiente e orientações para gerar arquivos locais.
| `scripts/` | Automação de deploy, validação de manifests e tarefas recorrentes.

Pipelines de CI/CD, testes e scripts adicionais podem ser adicionados, mas estes diretórios devem ser mantidos para preservar a compatibilidade com os utilitários do template.

## Como iniciar um projeto derivado

1. Clique em **Use this template** (ou faça um fork) para gerar um novo repositório.
2. Atualize o nome do projeto e os metadados no `README.md` recém-criado com o contexto da sua stack.
3. Revise os arquivos de `compose/` e `env/` para alinhar serviços, portas e variáveis às suas necessidades.
4. Ajuste a documentação em `docs/` seguindo as orientações de personalização descritas neste template (com foco em
   [`docs/local/`](docs/local/README.md) para registrar detalhes específicos da sua stack).
5. Execute os scripts de validação (`scripts/check_structure.sh`, `scripts/validate_compose.sh`) antes do primeiro commit.

## Fluxo sugerido para novos repositórios

1. **Modelagem** – registre objetivos, requisitos e decisões iniciais nos ADRs (`docs/ADR/`).
2. **Infraestrutura** – crie os manifests em `compose/` e modele as variáveis correspondentes em `env/`.
3. **Automação** – adapte os scripts existentes para a nova stack e documente o uso em `docs/OPERATIONS.md`.
4. **Runbooks** – personalize os guias operacionais (`docs/core.md`, `docs/media.md`, etc.) para refletir ambientes reais.
5. **Qualidade** – configure testes e validações adicionais em `.github/workflows/` conforme necessário.

## Documentação

- [Índice completo](docs/README.md)
- [Visão geral da stack](docs/OVERVIEW.md)
- [Estrutura do template](docs/STRUCTURE.md)
- [Operação e scripts](docs/OPERATIONS.md)
- [Combinações de manifests Compose](docs/COMPOSE_GUIDE.md)
- [Guia de variáveis de ambiente](env/README.md)
- [Integração de rede](docs/NETWORKING_INTEGRATION.md)
- [Backup & Restauração genéricos](docs/BACKUP_RESTORE.md)
- [Registro de decisões arquiteturais](docs/ADR/)
- [Boas práticas para herdeiros do template](docs/TEMPLATE_BEST_PRACTICES.md)
- [Apontamentos locais da stack](docs/local/README.md)

## Customização local

Repositórios derivados devem concentrar contexto específico em `docs/local/`. O arquivo [`docs/local/README.md`](docs/local/README.md)
atua como índice para runbooks, decisões e dependências particulares da sua stack. Ao manter este conteúdo isolado:

- minimizamos conflitos durante rebases ou merges a partir do template;
- fica claro para novas pessoas contribuidoras onde encontrar detalhes exclusivos do repositório;
- evitamos edições frequentes neste `README.md`, que permanece alinhado às instruções gerais do template.

Ao personalizar o projeto, priorize as alterações em `docs/local/` e complemente os demais arquivos apenas quando necessário.

## Atualizando a partir do template original

Repositórios derivados podem reaplicar suas customizações sobre a versão mais recente do template usando
`scripts/update_from_template.sh`. O fluxo sugerido é:

1. Configure o remote que aponta para o template, por exemplo `git remote add template git@github.com:org/template.git`.
2. Identifique o commit do template usado como base inicial (`ORIGINAL_COMMIT_ID`) e o primeiro commit local exclusivo
   (`FIRST_COMMIT_ID`).
3. Execute uma simulação informando os parâmetros via flags:

   ```bash
   scripts/update_from_template.sh \
     --remote template \
     --original-commit <hash-do-template-inicial> \
     --first-local-commit <hash-do-primeiro-commit-local> \
     --target-branch main \
     --dry-run
   ```

4. Remova `--dry-run` para aplicar o rebase e resolva possíveis conflitos antes de abrir um PR.
5. Finalize rodando os testes da stack (por exemplo, `python -m pytest` e `scripts/check_structure.sh`; adapte conforme
   descrito em [`docs/OPERATIONS.md`](docs/OPERATIONS.md)).

O script exibe mensagens claras sobre os comandos executados (`git fetch` seguido de `git rebase --onto`) e falha cedo caso
os commits informados não pertençam à branch atual.

## Testes automatizados

Para executar a suíte de testes localmente:

```bash
pip install -r requirements-dev.txt
python -m pytest
```

Os scripts shell também podem ser verificados com [ShellCheck](https://www.shellcheck.net/):

```bash
shellcheck scripts/*.sh
```

Adapte as ferramentas de lint e os testes para refletir a stack de cada projeto derivado.
