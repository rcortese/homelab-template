services:
  {{APP}}:
    # Adjust the ports exposed by this instance.
    ports:
      - "${{{PORT_VAR}}:-8080}:8080"
    environment:
      # Public URLs resolved by the reverse proxy.
      APP_PUBLIC_URL: ${APP_PUBLIC_URL:-}
      # URLs for external integrations (webhooks, callbacks, etc.).
      APP_WEBHOOK_URL: ${APP_WEBHOOK_URL:-}
