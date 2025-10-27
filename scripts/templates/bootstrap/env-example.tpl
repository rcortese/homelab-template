# Este arquivo complementa env/common.example.env. Copie ambos para env/local/.
# Obrigatório ao expor URLs públicas • Endereço base divulgado para usuários desta instância.
APP_PUBLIC_URL=https://{{APP}}.domain.example
# Opcional • URL dedicada para webhooks ou callbacks externos.
APP_WEBHOOK_URL=https://hooks.domain.example/{{APP}}
# Opcional • Porta exposta no host para acesso à aplicação.
{{PORT_VAR}}=8080
# Opcional • Liste serviços monitorados pelo health-check automático.
# HEALTH_SERVICES={{APP}}
# Opcional • Inclua overlays adicionais após o override principal da instância.
# COMPOSE_EXTRA_FILES=compose/overlays/observability.yml
