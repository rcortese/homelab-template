# Guia de onboarding do template

Este roteiro resume o fluxo inicial recomendado para quem está derivando o template. Ele consolida os pré-requisitos, o bootstrap dos arquivos `.env` e as validações obrigatórias antes dos primeiros commits.

## 1. Instale as dependências base

Garanta que a máquina de desenvolvimento tenha as ferramentas abaixo instaladas (mesmo quando for utilizar ambientes remotos como codespaces ou VMs temporárias):

- Docker Engine
- Docker Compose v2
- Python 3.x
- Ferramentas de lint/format para shell (`shellcheck`, `shfmt` ou equivalentes)

> Consulte a seção [Pré-requisitos](../README.md#pré-requisitos) para detalhes adicionais e alternativas compatíveis.

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

O agregador `scripts/check_all.sh` encadeia exatamente a sequência de validações abaixo, que você também pode executar manualmente como detalhamento ou alternativa:

```bash
scripts/check_structure.sh
scripts/check_env_sync.py
scripts/validate_compose.sh
```

- [`scripts/check_structure.sh`](./OPERATIONS.md#scriptscheck_structuresh)
- [`scripts/check_env_sync.py`](./OPERATIONS.md#scriptscheck_env_syncpy)
- [`scripts/validate_compose.sh`](./OPERATIONS.md#scriptsvalidate_composesh)

## 5. Próximos passos

- Revise o [índice completo de documentação](./README.md) para localizar runbooks e guias específicos.
- Utilize [`docs/TEMPLATE_BEST_PRACTICES.md`](./TEMPLATE_BEST_PRACTICES.md) como referência ao adaptar o template.
- Centralize informações particulares do seu fork em [`docs/local/`](./local/README.md).

Seguir este roteiro garante que o repositório derivado começa com as convenções mínimas alinhadas ao template oficial.
