#!/bin/bash
set -euo pipefail

INV="${1:-inventory/hosts-ha-reference.yml}"
TARGET="${2:-}"
NEW_PRIMARY="${3:-}"

if [[ -z "$TARGET" ]]; then
    echo "用法: $0 <inventory> <mysql-host-to-remove> [new-primary-host]" >&2
    exit 1
fi

ARGS=(--scale-mysql-remove --target "$TARGET" -i "$INV")
if [[ -n "$NEW_PRIMARY" ]]; then
    ARGS+=(--new-primary "$NEW_PRIMARY")
fi

exec ./scripts/deploy_dedicated_routers.sh "${ARGS[@]}"
