#!/usr/bin/env bash
# shellcheck source=lib/compose_defaults.sh
source "$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/compose_defaults.sh"

main "$@"
