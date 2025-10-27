# Guia de combinações do Docker Compose

> Parte do [índice da documentação](./README.md). Consulte também a [Visão Geral](./OVERVIEW.md) e os runbooks específicos das instâncias ([core](./core.md) e [media](./media.md)).

As orientações completas sobre o wrapper `scripts/compose.sh` — incluindo ordem dos manifests, cadeia de arquivos `.env`, variáveis auxiliares e exemplos de personalização — foram consolidadas em [`docs/OPERATIONS.md`](./OPERATIONS.md#scriptscomposesh). O guia de operações descreve como o script monta o plano do Docker Compose para cada instância e como adaptar overlays temporários sem quebrar a estrutura do template.

## Como aplicar o fluxo padronizado

1. Garanta que os `.env` locais foram gerados conforme [`env/README.md`](../env/README.md#como-gerar-arquivos-locais).
2. Execute `scripts/compose.sh <instancia> <subcomando>` para carregar a combinação correta de manifests antes de delegar ao `docker compose`.
3. Para depurações pontuais, utilize `scripts/compose.sh --help` ou o modo `--` para acessar o Compose diretamente mantendo o mesmo contexto resolvido pelo wrapper.

```bash
# Exemplo rápido de uso
scripts/compose.sh core up -d
```

> Quando precisar revisar a lista exata de arquivos aplicados ou compartilhar o plano com outras pessoas, combine o wrapper com `scripts/describe_instance.sh <instancia> --format json` — o relatório gerado permanece alinhado ao fluxo documentado em `docs/OPERATIONS.md`.
