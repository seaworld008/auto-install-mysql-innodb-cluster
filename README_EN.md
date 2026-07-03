# MySQL InnoDB Cluster Automation

English summary for global discovery. The primary documentation is Chinese-first; this page gives international users enough context to evaluate the project and find the correct runbooks.

## What This Project Does

This repository provides an Ansible-based automation mainline for deploying and operating MySQL InnoDB Cluster with:

- MySQL Server and InnoDB Cluster
- MySQL Router
- HAProxy and Keepalived
- MySQL scale-out and scale-in workflows
- Router and load balancer shrink workflows
- Rolling configuration application
- Optional logical or physical backups

The project is intentionally converged around one runtime configuration file and one operator entrypoint:

- Runtime source of truth: `inventory/group_vars/all.yml`
- Main operator entrypoint: `scripts/deploy_dedicated_routers.sh`
- Compatibility wrapper only: `deploy.sh`

## Recommended Topology

```text
Application
  -> HAProxy VIP or DNS
  -> MySQL Router cluster
  -> MySQL InnoDB Cluster
```

Default high availability baseline:

| Layer | Baseline | Notes |
| --- | --- | --- |
| MySQL InnoDB Cluster | 3 nodes | One primary plus secondaries |
| MySQL Router | 2+ nodes | Dedicated router layer recommended |
| HAProxy + Keepalived | 2+ nodes | Shared entry through VIP or DNS |
| MySQL release line | 8.4 LTS by default | MySQL 8.0 compatibility retained |

## Quick Start

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -r requirements.txt
ansible-galaxy collection install -r collections/requirements.yml

vim inventory/hosts-with-dedicated-routers.yml
vim inventory/group_vars/all.yml

./scripts/deploy_dedicated_routers.sh --check-prereq -i inventory/hosts-with-dedicated-routers.yml
./scripts/deploy_dedicated_routers.sh --production-ready -i inventory/hosts-with-dedicated-routers.yml
./scripts/deploy_dedicated_routers.sh --status -i inventory/hosts-with-dedicated-routers.yml
```

Replace all `CHANGE_ME_*` placeholders before deployment. Production usage should rely on Ansible Vault, SSH keys, CI/CD secrets, or a dedicated secrets manager.

## Main Operations

All supported operator workflows should route through `scripts/deploy_dedicated_routers.sh`.

| Operation | Command |
| --- | --- |
| Full production candidate deployment | `--production-ready` |
| MySQL only | `--mysql-only` |
| Rolling configuration apply | `--apply-config` |
| Add MySQL node | `--scale-mysql-add` |
| Remove MySQL node | `--scale-mysql-remove` |
| Remove Router node | `--shrink-router` |
| Remove HAProxy node | `--shrink-lb` |
| Optional backup | `--backup` |
| Status check | `--status` |

## Local Validation

```bash
git diff --check
bash -n deploy.sh validate_deployment.sh scripts/*.sh
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --syntax-check
ansible-playbook -i inventory/hosts-ha-reference.yml playbooks/site.yml --syntax-check
ansible-playbook -i inventory/hosts-with-dedicated-routers.yml playbooks/site.yml --syntax-check
ansible-inventory -i inventory/hosts.yml --list
ansible-inventory -i inventory/hosts-ha-reference.yml --list
ansible-inventory -i inventory/hosts-with-dedicated-routers.yml --list
```

Optional advisory documentation lint:

```bash
npx --yes markdownlint-cli2
python -m pip install yamllint
yamllint .
```

## Documentation Map

- Chinese main README: `README.md`
- Quick start: `QUICK_START.md`
- Deployment guide: `DEPLOYMENT_COMPLETE_GUIDE.md`
- Pre-deployment checklist: `PRE_DEPLOYMENT_CHECKLIST.md`
- Server configuration runbook: `docs/runbooks/SERVER_CONFIGURATION.md`
- Troubleshooting runbook: `docs/runbooks/TROUBLESHOOTING.md`
- HA blueprint: `docs/reference/DEPLOYMENT_HA_BLUEPRINT_ZH.md`
- Architecture and evidence guide: `docs/reference/ARCHITECTURE_AND_EVIDENCE.md`
- Variable reference: `docs/reference/VARIABLE_REFERENCE.md`
- Backup and restore guide: `docs/runbooks/BACKUP_AND_RESTORE_GUIDE.md`
- Staging validation template: `docs/templates/staging-validation-record.md`
- Failover drill template: `docs/templates/failover-drill-record.md`
- Isolated restore drill template: `docs/templates/restore-drill-record.md`
- Historical analysis reports: `docs/reports/`

## Status Boundary

Static validation can prove that syntax and inventory parsing pass. It cannot prove production readiness, failover behavior, performance capacity, or backup recovery correctness. Real environment validation, staging failover drills, and isolated restore exercises are still required before production adoption.
