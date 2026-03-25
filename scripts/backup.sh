#!/bin/bash
set -euo pipefail

INV="${1:-inventory/hosts-ha-reference.yml}"
ansible-playbook -i "$INV" playbooks/backup.yml
