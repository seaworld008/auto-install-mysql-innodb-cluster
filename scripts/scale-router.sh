#!/bin/bash
set -euo pipefail
INV="${1:-inventory/hosts-ha-reference.yml}"
LIMIT="${2:-mysql_router}"
ansible-playbook -i "$INV" playbooks/scale-router.yml --limit "$LIMIT"
