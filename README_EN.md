# MySQL InnoDB Cluster Automation

**Deploy and operate MySQL high availability through one Ansible workflow.**

[![CI](https://github.com/seaworld008/auto-install-mysql-innodb-cluster/actions/workflows/ansible-ci.yml/badge.svg?branch=main)](https://github.com/seaworld008/auto-install-mysql-innodb-cluster/actions/workflows/ansible-ci.yml)
[![Release](https://img.shields.io/github/v/release/seaworld008/auto-install-mysql-innodb-cluster)](https://github.com/seaworld008/auto-install-mysql-innodb-cluster/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

[中文](README.md) · [Quick start](QUICK_START.md) · [Documentation](docs/index.md)

Ansible automation for **MySQL Server, InnoDB Cluster, MySQL Router, HAProxy and Keepalived**.
Built for DBAs, SREs and platform teams that want a shared workflow for installation, scaling,
rolling configuration changes and backups.

## Capabilities

- Deploy a three-member InnoDB Cluster with a dedicated Router layer and a highly available VIP.
- Connect applications through explicit read/write, read-only or optional read/write splitting ports.
- Add and remove MySQL members, shrink Router/LB tiers and apply configuration changes incrementally.
- Check member health, cluster identity, entry services, ports and unique VIP ownership.
- Run opt-in MySQL Shell logical or Percona XtraBackup physical backups; use isolated restore runbooks.
- Prepare local systemd-based Linux hosts for simulation using the same Ansible deployment entrypoint.

## Architecture

```text
Application → Keepalived VIP → HAProxy × 2 → MySQL Router × 2
                                             ↓
                             MySQL InnoDB Cluster × 3
                              Primary + 2 Secondaries
```

HAProxy forwards to Router. Router discovers the writable member from cluster metadata.
MySQL defaults to the 8.4 LTS release line; 8.0 is also configurable.

## Get started

The control node requires Python 3.12+; managed Linux hosts require Python 3.9+ and SSH access.

```bash
git clone https://github.com/seaworld008/auto-install-mysql-innodb-cluster.git
cd auto-install-mysql-innodb-cluster
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
ansible-galaxy collection install -r collections/requirements.yml
./scripts/setup-servers.sh
ansible-vault create inventory/vault.local.yml
```

Configure the generated inventory and encrypted credentials using the [quick start](QUICK_START.md).
Verify host fingerprints through a trusted channel before connecting. Then run:

```bash
./scripts/deploy_dedicated_routers.sh --check-prereq \
  -i inventory/hosts.local.yml --ask-vault-pass -e @inventory/vault.local.yml
./scripts/deploy_dedicated_routers.sh --production-ready \
  -i inventory/hosts.local.yml --ask-vault-pass -e @inventory/vault.local.yml
./scripts/deploy_dedicated_routers.sh --status \
  -i inventory/hosts.local.yml --ask-vault-pass -e @inventory/vault.local.yml
```

Runtime settings live in [`inventory/group_vars/all.yml`](inventory/group_vars/all.yml).
Real addresses and secrets belong in ignored local inventories, Ansible Vault or an external secret manager.

## Connect applications

| Workload | VIP | Direct Router |
| --- | --- | --- |
| Writes, transactions and read-after-write access | `3307` | `6446` |
| Read-only queries that tolerate replica lag | `3308` | `6447` |
| Optional automatic read/write splitting | `3309` | `6450` |

Start transactional applications with the explicit read/write endpoint. Validate driver, pool and
transaction behavior before choosing automatic splitting. See [application connections](docs/runbooks/APPLICATION_CONNECTIONS.md).

## Operate

Use the same entrypoint, inventory and Vault with `--mysql-only`, `--install-routers`,
`--configure-lb`, `--apply-config`, `--scale-mysql-add`, `--scale-mysql-remove`,
`--shrink-router`, `--shrink-lb`, `--backup` or `--status`.

Update inventory before adding nodes; explicitly select a new primary when removing the writer.
Backups are disabled by default and support local, NFS and rsync targets.
Existing Router identity and keyring are preserved during configuration convergence.
Plan maintenance windows and validate certificates, capacity, failover and isolated recovery for your environment.

## Documentation and contributing

- [Deployment guide](DEPLOYMENT_COMPLETE_GUIDE.md) and [pre-deployment checklist](PRE_DEPLOYMENT_CHECKLIST.md)
- [Operator guide](docs/runbooks/OPERATOR_GUIDE.md) and [variable reference](docs/reference/VARIABLE_REFERENCE.md)
- [Backup and restore](docs/runbooks/BACKUP_AND_RESTORE_GUIDE.md)
- [Local simulation](docs/runbooks/LOCAL_SIMULATION.md)
- [Contributing](CONTRIBUTING.md), [security policy](SECURITY.md) and [changelog](CHANGELOG.md)

Documentation is Chinese-first. Reproducible issues, deployment feedback and pull requests are welcome.
Licensed under the [MIT License](LICENSE).
