# Guia de variáveis de ambiente

Este diretório armazena modelos (`*.example.env`) e instruções para gerar arquivos locais em `env/local/`. Repositórios derivados devem adaptar estes exemplos ao seu conjunto de serviços, mantendo a documentação atualizada.

## Como gerar arquivos locais

1. Crie o diretório ignorado pelo Git:
   ```bash
   mkdir -p env/local
   ```
2. Copie os modelos relevantes:
   ```bash
   cp env/<alvo>.example.env env/local/<alvo>.env
   ```
3. Preencha os valores conforme o ambiente (desenvolvimento, laboratório, produção, etc.).

## Mapeamento das variáveis

Monte uma tabela semelhante à abaixo para cada arquivo `env/<alvo>.example.env`:

| Variável | Obrigatória? | Uso | Referência |
| --- | --- | --- | --- |
| `TZ` | Sim | Define timezone para logs e agendamentos. | `compose/base.yml`. |
| `APP_SECRET` | Sim | Chave utilizada para criptografar dados sensíveis. | `compose/base.yml`. |
| `APP_RETENTION_HOURS` | Opcional | Controla a retenção de registros/processos. | `compose/base.yml` e runbooks. |
| `APP_PUBLIC_URL` | Opcional | Define URL pública para links e cookies. | `compose/core.yml` (ou equivalente). |
| `SERVICE_NAME` | Opcional | Personaliza o nome do container ou alvo de logs. | `compose/<alvo>.yml`, `scripts/check_health.sh`. |
| `APP_DATA_DIR` | Opcional | Escolhe o diretório persistente utilizado nos volumes. | `compose/base.yml`, `scripts/deploy_instance.sh`. |
| `COMPOSE_EXTRA_FILES` | Opcional | Lista overlays adicionais aplicados após o override da instância (separados por espaço ou vírgula). | `scripts/deploy_instance.sh`, `scripts/validate_compose.sh`, `scripts/lib/compose_defaults.sh`. |

> Substitua a tabela pelos campos reais da sua stack. Utilize a coluna **Referência** para apontar onde a variável é consumida (manifests, scripts, infraestrutura externa, etc.).

## Boas práticas

- **Padronize nomes**: utilize prefixos (`APP_`, `DB_`, `CACHE_`) para agrupar responsabilidades.
- **Documente defaults seguros**: indique valores recomendados ou formatos esperados (ex.: URLs completas, chaves com tamanho mínimo).
- **Evite segredo no Git**: mantenha apenas modelos e documentação. Os arquivos em `env/local/` devem estar listados no `.gitignore`.
- **Sincronize com ADRs**: se novas variáveis forem introduzidas por decisões arquiteturais, referencie o ADR correspondente na tabela.

## Integração com scripts

Os scripts fornecidos pelo template aceitam `COMPOSE_ENV_FILE` para selecionar qual arquivo `.env` será utilizado. Documente, no runbook correspondente, como combinar variáveis e manifests para cada ambiente. Quando precisar ativar overlays específicos sem modificar scripts, adicione no `.env` algo como:

```env
COMPOSE_EXTRA_FILES=compose/overlays/observability.yml compose/overlays/metrics.yml
```

Esse padrão mantém as diferenças entre template e fork confinadas aos arquivos de configuração.
