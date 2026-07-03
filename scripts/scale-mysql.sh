#!/bin/bash
set -euo pipefail

INV="${1:-inventory/hosts-ha-reference.yml}"
LIMIT="${2:-}"

if [[ -z "$LIMIT" ]]; then
    echo "用法: $0 <inventory> <new-mysql-host-limit>" >&2
    exit 1
fi

exec ./scripts/deploy_dedicated_routers.sh --scale-mysql-add --limit "$LIMIT" -i "$INV"
