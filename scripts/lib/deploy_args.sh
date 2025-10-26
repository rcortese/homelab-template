#!/usr/bin/env bash

print_help() {
  cat <<'USAGE'
Uso: scripts/deploy_instance.sh <instancia> [flags]

Realiza um deploy guiado da instância (core/media), carregando automaticamente
os arquivos compose necessários (base + override da instância) e executando
validações auxiliares.

Argumentos posicionais:
  instancia       Nome da instância (ex.: core, media).

Flags:
  --dry-run       Apenas exibe os comandos que seriam executados.
  --force         Pula confirmações interativas (útil localmente ou em CI).
  --skip-structure  Não executa scripts/check_structure.sh antes do deploy.
  --skip-validate   Não executa scripts/validate_compose.sh antes do deploy.
  --skip-health     Não executa scripts/check_health.sh após o deploy.
  -h, --help      Mostra esta ajuda e sai.

Variáveis de ambiente relevantes:
  CI              Quando definida, assume modo não interativo (equivalente a --force).
USAGE
}

parse_deploy_args() {
  local instance=""
  local force=0
  local dry_run=0
  local run_structure=1
  local run_validate=1
  local run_health=1
  local show_help=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
    -h | --help)
      show_help=1
      shift
      continue
      ;;
    --force)
      force=1
      shift
      continue
      ;;
    --dry-run)
      dry_run=1
      shift
      continue
      ;;
    --skip-structure)
      run_structure=0
      shift
      continue
      ;;
    --skip-validate)
      run_validate=0
      shift
      continue
      ;;
    --skip-health)
      run_health=0
      shift
      continue
      ;;
    -*)
      echo "[!] Flag desconhecida: $1" >&2
      echo >&2
      print_help >&2
      return 1
      ;;
    *)
      if [[ -z "$instance" ]]; then
        instance="$1"
        shift
        continue
      fi
      echo "[!] Parâmetro inesperado: $1" >&2
      echo >&2
      print_help >&2
      return 1
      ;;
    esac
  done

  if [[ $show_help -eq 0 && -z "$instance" ]]; then
    echo "[!] Instância não informada." >&2
    echo >&2
    print_help >&2
    return 1
  fi

  printf 'declare -A DEPLOY_ARGS=(\n'
  printf '  [INSTANCE]=%q\n' "$instance"
  printf '  [FORCE]=%q\n' "$force"
  printf '  [DRY_RUN]=%q\n' "$dry_run"
  printf '  [RUN_STRUCTURE]=%q\n' "$run_structure"
  printf '  [RUN_VALIDATE]=%q\n' "$run_validate"
  printf '  [RUN_HEALTH]=%q\n' "$run_health"
  printf '  [SHOW_HELP]=%q\n' "$show_help"
  printf ')\n'
}
