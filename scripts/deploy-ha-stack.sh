#!/bin/bash
set -euo pipefail

INVENTORY="${1:-inventory/hosts-ha-reference.yml}"

exec ./scripts/deploy_dedicated_routers.sh --production-ready -i "$INVENTORY"
