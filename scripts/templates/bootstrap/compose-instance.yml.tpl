services:
  {{APP}}:
    # Ajuste as portas expostas por esta instância.
    ports:
      - "${{{PORT_VAR}}:-8080}:8080"
    environment:
      # URLs públicas resolvidas pelo proxy reverso.
      APP_PUBLIC_URL: ${APP_PUBLIC_URL:-}
      # URLs para integrações externas (webhooks, callbacks, etc.).
      APP_WEBHOOK_URL: ${APP_WEBHOOK_URL:-}
