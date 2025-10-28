# Runbooks de aplicações

Esta pasta centraliza a documentação específica de cada aplicação gerenciada pela stack. Utilize-a para registrar arquitetura, variáveis sensíveis, fluxos operacionais e estratégias de monitoração que não cabem na documentação genérica do template.

## Como estruturar os arquivos `<app>.md`

Cada aplicação deve ter um arquivo dedicado, nomeado com o identificador curto da app (por exemplo, `docs/apps/minio.md`). O conteúdo pode seguir o seguinte formato sugerido, equivalente ao template `scripts/templates/bootstrap/doc-app.md.tpl`:

```markdown
# <Título da aplicação> (<slug>)

## Visão geral
- Papel na stack
- Dependências externas
- Critérios de disponibilidade

## Manifests
- Arquivos Compose relacionados (bases e instâncias)

## Variáveis de ambiente
- Principais arquivos `env/*.example.env` afetados

## Fluxos operacionais
- Passos de deploy, validações e tarefas de rotina

## Monitoramento e alertas
- Métricas, painéis e notificações críticas

## Referências
- Documentações externas, guias internos e links úteis
```

Adapte os blocos acima conforme necessário para refletir o comportamento real da aplicação e mantenha as instruções atualizadas à medida que o serviço evoluir.

## Como vincular ao índice principal

Sempre que criar ou atualizar um runbook em `docs/apps/`, adicione o link correspondente na seção **Aplicações** do [`docs/README.md`](../README.md). Dessa forma, forks do template preservam um índice único e fácil de navegar para todos os serviços documentados.

Também é recomendado referenciar este diretório em outros guias (por exemplo, `docs/OPERATIONS.md`) sempre que houver procedimentos que dependam de instruções específicas de uma aplicação.
