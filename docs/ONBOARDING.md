# Guia de onboarding do template

Este roteiro resume o fluxo inicial recomendado para quem está derivando o template. Ele consolida os pré-requisitos, o bootstrap dos arquivos `.env` e as validações obrigatórias antes dos primeiros commits. Este documento é o checklist oficial das validações iniciais do template.

## 1. Instale as dependências base

Esta é a referência canônica de dependências exigidas pelo template. Garanta que a máquina de desenvolvimento tenha as
ferramentas abaixo instaladas (mesmo quando for utilizar ambientes remotos como codespaces ou VMs temporárias):

- Docker Engine **>= 24.x** (ou versão estável equivalente que ofereça suporte ao Compose v2 integrado)
- Docker Compose **v2.20+** (para compatibilidade com perfis e validações atuais)
- Python **>= 3.11** (necessário para executar scripts de automação e suítes de testes)
- Ferramentas de lint/format para shell: `shellcheck` **>= 0.9.0** e `shfmt` **>= 3.6.0** (ou alternativas compatíveis configuradas
  nos pipelines locais)

> Sempre que o template exigir novas ferramentas ou versões mínimas, esta lista será atualizada primeiro.

## 2. Prepare os arquivos `.env`

1. Gere o diretório ignorado pelo Git:
   ```bash
   mkdir -p env/local
   ```
2. Execute o bootstrap para criar manifests, modelos `.env` e documentação opcional de uma nova instância:
   ```bash
   scripts/bootstrap_instance.sh <aplicacao> <instancia>
   # acrescente --with-docs para gerar os esboços em docs/apps/
   ```
3. Preencha os arquivos gerados em `env/<instancia>.example.env` e copie-os para `env/local/` conforme descrito no [guia de variáveis](../env/README.md#como-gerar-arquivos-locais).

> Quando apenas reutilizar instâncias existentes do template, copie manualmente os modelos `env/*.example.env` para `env/local/` e atualize os valores sensíveis seguindo o mesmo guia.

## 3. Configure o ambiente Python

Instale as dependências de desenvolvimento necessárias para executar as validações locais:

```bash
pip install -r requirements-dev.txt
```

## 4. Rode as validações consolidadas

Com os `.env` locais criados e as dependências instaladas, execute:

```bash
scripts/check_all.sh
```

O agregador `scripts/check_all.sh` executa, na ordem abaixo, as validações estruturais essenciais do template e encerra imediatamente quando alguma delas falha:

- `scripts/check_structure.sh` – confirma se diretórios e arquivos obrigatórios continuam presentes.
- `scripts/check_env_sync.py` – verifica se manifests Compose e arquivos `env/*.example.env` permanecem sincronizados.
- `scripts/validate_compose.sh` – valida as combinações padrão de manifests para os perfis ativos.

Utilize `scripts/run_quality_checks.sh` quando quiser rodar rapidamente a bateria base de qualidade sem percorrer todas as validações — acrescente `--no-lint` caso deseje apenas executar `pytest`.

## 5. Próximos passos

- Revise o [índice completo de documentação](./README.md) para localizar runbooks e guias específicos.
- Utilize [`docs/TEMPLATE_BEST_PRACTICES.md`](./TEMPLATE_BEST_PRACTICES.md) como referência ao adaptar o template.
- Centralize informações particulares do seu fork em [`docs/local/`](./local/README.md).

Seguir este roteiro garante que o repositório derivado começa com as convenções mínimas alinhadas ao template oficial.
