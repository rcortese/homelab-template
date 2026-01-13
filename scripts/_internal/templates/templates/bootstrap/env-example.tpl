# This file complements env/common.example.env. Copy both to env/local/.
# Required when exposing public URLs • Base address shared with users of this instance.
APP_PUBLIC_URL=https://{{APP}}.domain.example
# Optional • Dedicated URL for webhooks or external callbacks.
APP_WEBHOOK_URL=https://hooks.domain.example/{{APP}}
# Optional • Host-exposed port for application access.
{{PORT_VAR}}=8080
# Optional • List services monitored by the automatic health check.
# HEALTH_SERVICES={{APP}}
# Optional • Include additional compose files after the instance primary override.
# COMPOSE_EXTRA_FILES=compose/extra/observability.yml
