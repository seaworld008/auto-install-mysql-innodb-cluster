# AGENTS.md

This repository maintains a single production mainline for deploying and operating MySQL InnoDB Cluster with Router, HAProxy, Keepalived, scaling workflows, and optional logical backups.

## Mission

Keep this repo maintainable, production-oriented, and converged.
Do not introduce parallel deployment flows, duplicate runtime configs, or "temporary" sidecar scripts that become permanent.

## Single Sources Of Truth

- Runtime config: `inventory/group_vars/all.yml`
- Main operator entrypoint: `scripts/deploy_dedicated_routers.sh`
- Compatibility wrapper only: `deploy.sh`
- CI static quality gate: `.github/workflows/ansible-ci.yml`
- Main user docs:
  - `README.md`
  - `DEPLOYMENT_COMPLETE_GUIDE.md`
  - `QUICK_START.md`
  - `PRE_DEPLOYMENT_CHECKLIST.md`

Historical reference only, not runtime truth:

- `inventory/group_vars/all-8c32g-optimized.yml`
- `inventory/group_vars/all-original-10k-config.yml`

## Required Workflow

When changing behavior:

1. Change runtime config in `inventory/group_vars/all.yml`
2. Change playbooks/templates/scripts that consume it
3. Sync the main docs
4. Run static validation
5. Run Ansible syntax/inventory validation
6. Commit only after the above passes

## Main Supported Operations

All should route through `scripts/deploy_dedicated_routers.sh`:

- `--production-ready`
- `--mysql-only`
- `--apply-config`
- `--scale-mysql-add`
- `--scale-mysql-remove`
- `--shrink-router`
- `--shrink-lb`
- `--backup`
- `--status`

If adding a new operation, prefer extending this script instead of creating a new top-level workflow.

## Config Rules

- Do not add new runtime config copies.
- Add new hardware/capacity variants under `mysql_config_profiles` in `inventory/group_vars/all.yml`.
- `scripts/config_manager.sh` should only switch `mysql_hardware_profile`.
- If a parameter is defined, make sure it actually takes effect in a template, playbook, or bootstrap command.

## Idempotency Rules

Preserve or improve idempotency:

- Re-running deployment should not destroy healthy nodes.
- Router should not re-bootstrap unless explicitly requested.
- Config application should be rolling where possible.
- Destructive operations must be explicit.
- Backups must remain opt-in by default.

## Validation Rules

Minimum expected checks before claiming completion:

- YAML parses successfully
- Shell scripts pass `bash -n`
- `git diff --check` passes
- `ansible-playbook ... --syntax-check` passes for primary inventories
- `ansible-inventory --list` passes for primary inventories

Required collections are declared in:

- `collections/requirements.yml`

## High-Risk Files

Treat these as sensitive:

- `inventory/group_vars/all.yml`
- `playbooks/install-mysql.yml`
- `playbooks/configure-cluster.yml`
- `playbooks/install-router.yml`
- `playbooks/backup.yml`
- `roles/mysql-server/templates/my.cnf.j2`
- `scripts/deploy_dedicated_routers.sh`

Changes here usually require doc updates too.

## Backups

Optional backup flow is controlled by `backup_config` in `inventory/group_vars/all.yml`.

Supported targets:

- `local`
- `nfs`
- `rsync`

Current backup implementation is logical backup via MySQL Shell dump.

## What Not To Claim

Do not claim:

- full production readiness from static checks alone
- real failover/recovery proof without staging or live environment execution
- real backup/restore verification unless it has been executed end-to-end

Accurate wording:

- "Static validation passed"
- "Ansible syntax and inventory validation passed"
- "Real environment validation still pending"
