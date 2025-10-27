# Integração com infraestrutura externa

> Utilize este documento para descrever como a stack derivada interage com componentes fora do repositório (rede, autenticação, observabilidade, etc.).

## Como documentar dependências

1. **Componentes externos** — liste serviços terceiros (reverse proxies, DNS, túneis, fila de mensagens, storage) responsáveis por expor ou suportar a stack.
2. **Responsáveis** — identifique times ou repositórios que mantêm cada componente.
3. **Contratos** — descreva endpoints, portas, domínios, chaves de API e requisitos de autenticação.
4. **Checklists de sincronização** — detalhe etapas obrigatórias sempre que uma mudança afetar os componentes externos.

## Exemplo de tabela

| Componente | Responsável | Responsabilidades | Entradas/Saídas |
| --- | --- | --- | --- |
| Proxy reverso | Equipe de plataforma | Terminação TLS, roteamento de hostnames, headers de segurança. | Recebe tráfego público → encaminha para os manifests `compose/base.yml` + [`compose/<instância>.yml`](../compose/core.yml) + `compose/apps/<app>/<instância>.yml`. |
| DNS interno | Time de rede | Publica registros para ambientes internos/externos. | Atualizar registros `A`/`CNAME` após mudanças de host. |
| Observabilidade | SRE | Coleta métricas e logs, gera alertas. | Dashboards e alertas que monitoram health-checks documentados no runbook. |

Substitua a tabela acima pelos componentes reais da sua infraestrutura.

## Fluxo recomendado para mudanças

1. Abra tickets ou PRs nos repositórios responsáveis pelos componentes afetados.
2. Atualize variáveis de ambiente e manifests neste repositório para refletir os novos valores (domínios, portas, credenciais).
3. Execute scripts de validação e siga os runbooks para aplicar o change.
4. Documente resultados (logs de implantação, validações externas) e referencie-os aqui.

## Incidentes e troubleshooting

- Registre como acionar equipes responsáveis por cada componente externo.
- Documente comandos úteis (ex.: `dig`, `curl`, `traceroute`, ferramentas de observabilidade).
- Mantenha um histórico de incidentes relevantes com links para post-mortems ou ADRs que tenham ajustado a integração.

## Documentos relacionados

- Runbooks de ambientes (`docs/core.md`, `docs/media.md` ou equivalentes)
- Guia de variáveis (`env/README.md`)
- ADRs que formalizam integrações críticas
