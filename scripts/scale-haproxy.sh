#!/bin/bash
set -euo pipefail
INV="${1:-inventory/hosts-ha-reference.yml}"
LIMIT="${2:-haproxy_lb}"
ansible-playbook -i "$INV" playbooks/scale-haproxy.yml --limit "$LIMIT"
