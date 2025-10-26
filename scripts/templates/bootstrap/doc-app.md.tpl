# {{APP_TITLE}} ({{APP}})

> Substitua os blocos abaixo com detalhes reais da aplicação assim que o bootstrap for concluído.

## Visão geral

- Papel na stack:
- Dependências externas:
- Critérios de disponibilidade:

## Manifests

- `compose/apps/{{APP}}/base.yml`
- `compose/apps/{{APP}}/{{INSTANCE}}.yml`
- `compose/base.yml`

## Variáveis de ambiente

- `env/common.example.env`
- `env/{{INSTANCE}}.example.env`

## Fluxos operacionais

1. Atualize `compose/apps/{{APP}}/{{INSTANCE}}.yml` com portas, volumes e secrets reais.
2. Preencha `env/{{INSTANCE}}.example.env` com orientações específicas do ambiente.
3. Rode `scripts/validate_compose.sh` garantindo que a nova combinação está válida.
4. Registre verificações adicionais no `docs/OPERATIONS.md` conforme necessário.

## Monitoramento e alertas

- Serviços monitorados:
- Dashboards e painéis:
- Alertas críticos:

## Referências

- Links úteis:
- Documentação adicional:
