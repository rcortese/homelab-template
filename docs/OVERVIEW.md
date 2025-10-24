# Visão Geral

> Parte do [índice da documentação](./README.md). Utilize em conjunto com [Operação](./OPERATIONS.md) e com o guia de [Integração de Rede](./NETWORKING_INTEGRATION.md) para aplicar as decisões descritas aqui e conectar-se a integrações externas.

## Topologia

- **Core (<core-host>)**: plano de controle do serviço principal (APIs, agendadores e integrações críticas). Exposição externa via túnel/proxy dedicado (ex.: Cloudflared → `app.domain.com`). Cada repositório derivado deve substituir `<core-host>` pelo hostname correspondente e ajustar as configurações de rede em [NETWORKING_INTEGRATION.md](./NETWORKING_INTEGRATION.md).
- **Media (<media-host>)**: workloads pesados e tarefas de dados. Sem exposição pública direta. Foco em processamento local. Cada repositório derivado deve substituir `<media-host>` pelo hostname correspondente e revisar as regras de proxy/documentação cruzada em [NETWORKING_INTEGRATION.md](./NETWORKING_INTEGRATION.md).
  - Use `compose/media.yml` para montar `/mnt/user` (ou `${MEDIA_HOST_PATH}`) como `/srv/media` dentro do contêiner e personalize conforme necessário (ex.: ajuste `${MEDIA_HOST_PATH}` conforme a sua infraestrutura).

## Comunicação entre instâncias

- **Recomendado:** MQTT (pub/sub) ou Webhooks internos.
- **Não trafegar binários** entre instâncias; passar **paths/metadados** e executar na instância media via SSH/CLI.

## Padrões

- `correlation_id` em todos os fluxos e logs.
- Idempotência: consumidores devem ignorar mensagens repetidas.
- Retenção: `APP_RETENTION_HOURS` para limitar histórico e economizar armazenamento.
