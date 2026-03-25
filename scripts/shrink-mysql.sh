#!/bin/bash
set -euo pipefail

INV="${1:-inventory/hosts-ha-reference.yml}"
TARGET="${2:-}"
NEW_PRIMARY="${3:-}"

if [[ -z "$TARGET" ]]; then
    echo "用法: $0 <inventory> <mysql-host-to-remove> [new-primary-host]" >&2
    exit 1
fi

EXTRA_VARS=("mysql_shrink_target=$TARGET")
if [[ -n "$NEW_PRIMARY" ]]; then
    EXTRA_VARS+=("mysql_shrink_new_primary=$NEW_PRIMARY")
fi

ansible-playbook -i "$INV" playbooks/shrink-mysql.yml --extra-vars "${EXTRA_VARS[*]}"
