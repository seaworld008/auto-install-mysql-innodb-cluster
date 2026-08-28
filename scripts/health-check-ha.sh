#!/bin/bash

# Fail-closed HA health check. Credentials stay inside Ansible variables and are
# never interpolated into the local process command line.

set -euo pipefail

INV="${1:-inventory/hosts-ha-reference.yml}"
if [[ $# -gt 0 ]]; then
    shift
fi
ANSIBLE_ARGS=("$@")

if [[ ! -f "$INV" ]]; then
    echo "inventory 文件不存在: $INV" >&2
    exit 1
fi

if ! command -v ansible-playbook >/dev/null 2>&1; then
    echo "缺少依赖: ansible-playbook" >&2
    exit 1
fi

echo "[1/1] 执行 HA 预检查与运行时健康检查"
health_command=(ansible-playbook -i "$INV")
if (( ${#ANSIBLE_ARGS[@]} > 0 )); then
    health_command+=("${ANSIBLE_ARGS[@]}")
fi
health_command+=(playbooks/validate-ha.yml)
ANSIBLE_STDOUT_CALLBACK=default exec "${health_command[@]}"
