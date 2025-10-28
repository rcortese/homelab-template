# Homelab service template

Este repositório serve como **template reutilizável** para stacks autocontidas. Ele reúne infraestrutura como código, scripts de operação e documentação sob uma mesma convenção para facilitar forks ou projetos derivados.

Se você acabou de derivar o template, comece pelo [guia de onboarding](docs/ONBOARDING.md) para seguir o fluxo inicial recomendado. Em seguida, utilize a seção [Documentação e customização local](#documentacao-e-customizacao-local) deste arquivo para se orientar na organização dos materiais.

Mantemos este arquivo genérico para facilitar a sincronização com novas versões do template. Informações específicas da sua stack devem ser descritas nos apontamentos locais indicados em [Documentação e customização local](#documentacao-e-customizacao-local).

## Pré-requisitos

Antes de começar, confira a seção de dependências no [guia de onboarding](docs/ONBOARDING.md). Lá mantemos a lista completa e
sempre atualizada de ferramentas necessárias (incluindo versões mínimas e alternativas compatíveis) para preparar o ambiente.

### Checklist rápido

Execute o passo a passo do [guia de onboarding](docs/ONBOARDING.md) para preparar ambiente e validações.

> Quando criar um guia de onboarding específico da stack, replique esta sequência para manter as instruções alinhadas entre os documentos.

## Conteúdo obrigatório

Todo repositório derivado deve manter o conjunto mínimo de diretórios descrito no template. Para a relação completa — fonte única de verdade — consulte a [tabela de diretórios obrigatórios em `docs/STRUCTURE.md`](docs/STRUCTURE.md#diretórios-obrigatórios). Ela detalha finalidades, exemplos de conteúdo e serve como referência central para atualizações estruturais.

Pipelines de CI/CD, testes e scripts adicionais podem ser adicionados, mas os diretórios listados na tabela devem ser mantidos para preservar a compatibilidade com os utilitários do template.

## Como iniciar um projeto derivado

1. Clique em **Use this template** (ou faça um fork) para gerar um novo repositório.
2. Atualize o nome do projeto e os metadados no `README.md` recém-criado com o contexto da sua stack.
3. Revise os arquivos de `compose/` e `env/` para alinhar serviços, portas e variáveis às suas necessidades.
4. Ajuste a documentação em `docs/` seguindo as orientações descritas na seção [Documentação e customização local](#documentacao-e-customizacao-local) deste template.
5. Execute o fluxo de validação (`scripts/check_all.sh`) antes do primeiro commit.

## Fluxo sugerido para novos repositórios

1. **Modelagem** – registre objetivos, requisitos e decisões iniciais nos ADRs (`docs/ADR/`).
2. **Infraestrutura** – crie os manifests em `compose/` e modele as variáveis correspondentes em `env/`.
3. **Automação** – adapte os scripts existentes para a nova stack e documente o uso em `docs/OPERATIONS.md`.
4. **Runbooks** – personalize os guias operacionais (`docs/core.md`, `docs/media.md`, etc.) para refletir ambientes reais.
5. **Qualidade** – mantenha `.github/workflows/` com `template-quality.yml` intacto e adicione workflows extras conforme necessário, documentando ajustes seguros em [`docs/ci-overrides.md`](docs/ci-overrides.md).

<a id="documentacao-e-customizacao-local"></a>
## Documentação e customização local

Centralize sua navegação pelo [índice em `docs/README.md`](docs/README.md), que organiza o ciclo de vida da stack e indica quando aprofundar cada tópico. Quando precisar registrar runbooks, decisões ou dependências específicas, utilize o diretório [`docs/local/`](docs/local/README.md) como ponto de entrada para os materiais particulares da sua stack.

Ao concentrar as personalizações nesses materiais você obtém:
- menos conflitos durante rebases ou merges a partir do template;
- um local dedicado onde encontrar detalhes exclusivos do repositório;
- menos edições neste `README.md`, que permanece alinhado às instruções gerais do template.

Assim, o restante do template continua servindo como referência e só exige ajustes pontuais quando necessário.

## Atualizando a partir do template original

Esta seção é a referência canônica para o fluxo de atualização do template. Qualquer resumo em outros documentos
aponta de volta para estas instruções.

Repositórios derivados podem reaplicar suas customizações sobre a versão mais recente do template usando
`scripts/update_from_template.sh`. O fluxo sugerido é:

1. Configure o remote que aponta para o template, por exemplo `git remote add template git@github.com:org/template.git`.
2. Identifique o commit do template usado como base inicial (`ORIGINAL_COMMIT_ID`) e o primeiro commit local exclusivo
   (`FIRST_COMMIT_ID`). Utilize `scripts/detect_template_commits.sh` para calcular automaticamente esses valores e
   persistir o resultado em `env/local/template_commits.env` (o script cria o diretório caso não exista).
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

