# Homelab service template

Este repositório serve como **template reutilizável** para stacks autocontidas. Ele reúne infraestrutura como código, scripts de operação e documentação sob uma mesma convenção para facilitar forks ou projetos derivados.

Se você acabou de derivar o template, comece pelo [guia de onboarding](docs/ONBOARDING.md) para seguir o fluxo inicial recomendado. Para uma visão completa da documentação utilize o [índice em `docs/README.md`](docs/README.md).

Mantemos este arquivo genérico para facilitar a sincronização com novas versões do template. Informações específicas da sua
stack devem ser descritas nos apontamentos locais indicados em [Customização local](#customização-local).

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
4. Ajuste a documentação em `docs/` seguindo as orientações de personalização descritas neste template (com foco em
   [`docs/local/`](docs/local/README.md) para registrar detalhes específicos da sua stack).
5. Execute o fluxo de validação (`scripts/check_all.sh`) antes do primeiro commit.

## Fluxo sugerido para novos repositórios

1. **Modelagem** – registre objetivos, requisitos e decisões iniciais nos ADRs (`docs/ADR/`).
2. **Infraestrutura** – crie os manifests em `compose/` e modele as variáveis correspondentes em `env/`.
3. **Automação** – adapte os scripts existentes para a nova stack e documente o uso em `docs/OPERATIONS.md`.
4. **Runbooks** – personalize os guias operacionais (`docs/core.md`, `docs/media.md`, etc.) para refletir ambientes reais.
5. **Qualidade** – configure testes e validações adicionais em `.github/workflows/` conforme necessário.

## Documentação

Comece pelo [índice em `docs/README.md`](docs/README.md) para entender o panorama geral e escolher o próximo passo. Em seguida, personalize os runbooks específicos da sua stack em [`docs/local/`](docs/local/README.md) mantendo o restante como referência de template.

O índice principal está dividido por etapas do ciclo de vida da stack: primeiro orienta o onboarding e a modelagem inicial, depois organiza referências de infraestrutura, automação e operações, e por fim aponta os materiais para customizações locais. Dessa forma você encontra rapidamente o tipo de conteúdo desejado sem precisar percorrer cada arquivo individualmente.

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

## Testes automatizados

Para executar a suíte de testes localmente:

```bash
pip install -r requirements-dev.txt
python -m pytest
```

Os scripts shell, inclusive os que residem em subdiretórios como `scripts/lib/`, também podem (e devem) ser verificados com [ShellCheck](https://www.shellcheck.net/):

```bash
shellcheck scripts/*.sh scripts/lib/*.sh
```

Adapte as ferramentas de lint e os testes para refletir a stack de cada projeto derivado.
