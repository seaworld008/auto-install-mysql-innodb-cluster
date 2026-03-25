#!/bin/bash
set -euo pipefail

INV="${1:-inventory/hosts-ha-reference.yml}"
LIMIT="${2:-}"

if [[ -z "$LIMIT" ]]; then
    echo "用法: $0 <inventory> <haproxy-host-limit>" >&2
    exit 1
fi

ansible-playbook -i "$INV" playbooks/shrink-haproxy.yml --limit "$LIMIT"
