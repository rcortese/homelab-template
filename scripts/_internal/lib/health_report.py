import base64
import json
import os


def load_list(env_key: str) -> list[str]:
    return [entry for entry in os.environ.get(env_key, "").split() if entry]


def build_service_entries(service_payload: str) -> list[dict[str, object]]:
    entries: list[dict[str, object]] = []
    for line in service_payload.splitlines():
        if not line:
            continue
        parts = line.split("::", 2)
        if len(parts) != 3:
            continue
        name, status, encoded = parts
        log_text = ""
        log_b64 = encoded if encoded else None
        if encoded:
            try:
                log_text = base64.b64decode(encoded.encode()).decode("utf-8", errors="replace")
            except Exception:
                log_text = ""
        entry = {
            "service": name,
            "status": status,
            "log": log_text,
        }
        if log_b64 is not None:
            entry["log_b64"] = log_b64
        entries.append(entry)
    return entries


def main() -> None:
    compose_ps_text = os.environ.get("COMPOSE_PS_TEXT", "")
    compose_ps_json_raw = os.environ.get("COMPOSE_PS_JSON", "")
    primary_targets = load_list("PRIMARY_LOG_SERVICES")
    auto_targets = load_list("AUTO_LOG_SERVICES")
    all_targets = load_list("ALL_LOG_SERVICES")
    failed_services = load_list("FAILED_SERVICES_STR")
    log_success = os.environ.get("LOG_SUCCESS_FLAG", "false").lower() == "true"
    instance = os.environ.get("INSTANCE_NAME", "") or None

    services_entries = build_service_entries(os.environ.get("SERVICE_PAYLOAD", ""))

    compose_section: dict[str, object] = {"raw": compose_ps_text}
    if compose_ps_json_raw:
        try:
            compose_section["parsed"] = json.loads(compose_ps_json_raw)
        except json.JSONDecodeError:
            compose_section["parsed_error"] = "invalid_json"
            compose_section["parsed_raw"] = compose_ps_json_raw

    summary_status = "ok" if not failed_services else "degraded"

    result = {
        "format": "json",
        "status": summary_status,
        "instance": instance,
        "compose": compose_section,
        "targets": {
            "requested": primary_targets,
            "automatic": auto_targets,
            "all": all_targets,
        },
        "logs": {
            "entries": services_entries,
            "failed": failed_services,
            "has_success": log_success,
            "total": len(services_entries),
            "successful": sum(1 for entry in services_entries if entry.get("status") == "ok"),
        },
    }

    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
