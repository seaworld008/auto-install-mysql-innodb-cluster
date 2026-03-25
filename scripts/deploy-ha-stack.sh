#!/bin/bash
set -euo pipefail

INVENTORY="${1:-inventory/hosts-ha-reference.yml}"

echo "[1/3] HA 预检查"
ansible-playbook -i "$INVENTORY" playbooks/preflight-ha.yml

echo "[2/3] 全量部署（MySQL + Cluster + Router + HAProxy）"
ansible-playbook -i "$INVENTORY" playbooks/site.yml

echo "[3/4] 执行健康检查"
./scripts/health-check-ha.sh "$INVENTORY"

echo "[4/4] 部署完成，请执行 docs/MYSQL80_CLUSTER_CROSS_VALIDATION.md 运行时校验"
