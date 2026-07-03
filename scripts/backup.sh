#!/bin/bash
set -euo pipefail

INV="${1:-inventory/hosts-ha-reference.yml}"
exec ./scripts/deploy_dedicated_routers.sh --backup -i "$INV"
