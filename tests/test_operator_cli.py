from __future__ import annotations

import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import textwrap
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
DEPLOY_SCRIPT = REPOSITORY_ROOT / "scripts" / "deploy_dedicated_routers.sh"
HEALTH_SCRIPT = REPOSITORY_ROOT / "scripts" / "health-check-ha.sh"


class OperatorCliTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_directory.cleanup)
        self.temp_path = Path(self.temp_directory.name)
        self.bin_path = self.temp_path / "bin"
        self.bin_path.mkdir()
        self.inventory_path = self.temp_path / "inventory.yml"
        self.inventory_path.write_text("---\nall: {}\n", encoding="utf-8")

        self._write_executable(
            "ansible",
            """
            #!/bin/bash
            set -euo pipefail
            if [[ -n "${FAKE_ANSIBLE_LOG:-}" ]]; then
              printf '%s\\n' "$*" >>"$FAKE_ANSIBLE_LOG"
            fi
            if [[ -n "${FAKE_ANSIBLE_FAIL_SERVICE:-}" ]] &&
               [[ "$*" == *"name=${FAKE_ANSIBLE_FAIL_SERVICE} "* ]]; then
              exit 17
            fi
            if [[ "$*" == *"--list-hosts"* ]]; then
              printf '  hosts (1):\\n    mysql-node1\\n'
            fi
            """,
        )
        self._write_executable(
            "ansible-playbook",
            """
            #!/bin/bash
            set -euo pipefail
            if [[ -n "${FAKE_PLAYBOOK_LOG:-}" ]]; then
              printf '%s\\n' "$*" >>"$FAKE_PLAYBOOK_LOG"
            fi
            exit "${FAKE_PLAYBOOK_EXIT:-0}"
            """,
        )
        self._write_executable(
            "ansible-inventory",
            """
            #!/usr/bin/env python3
            import json
            import os
            import sys

            common = {
                "keepalived_vip": "192.0.2.100",
                "haproxy_mysql_rw_port": 3307,
                "haproxy_mysql_ro_port": 3308,
                "haproxy_mysql_rwsplit_port": 3309,
                "mysql_router_port": 6446,
                "mysql_router_ro_port": 6447,
                "mysql_router_rwsplit_port": 6450,
                "mysql_ha_min_nodes": 3,
                "router_ha_min_nodes": 2,
                "haproxy_ha_min_nodes": 2,
            }
            hostvars = {
                "mysql-node1": dict(common),
                "mysql-node2": dict(common),
            }
            if os.environ.get("FAKE_INVENTORY_MODE") == "conflict":
                hostvars["mysql-node2"]["keepalived_vip"] = "192.0.2.101"
            if os.environ.get("FAKE_INVENTORY_LOG"):
                with open(
                    os.environ["FAKE_INVENTORY_LOG"],
                    "a",
                    encoding="utf-8",
                ) as log_file:
                    log_file.write(" ".join(sys.argv[1:]) + "\\n")
            print(json.dumps({"_meta": {"hostvars": hostvars}}))
            """,
        )

    def _write_executable(self, name: str, body: str) -> None:
        target = self.bin_path / name
        target.write_text(textwrap.dedent(body).lstrip(), encoding="utf-8")
        target.chmod(target.stat().st_mode | stat.S_IXUSR)

    def _run(
        self,
        script: Path,
        *arguments: str,
        environment: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        command_environment = os.environ.copy()
        command_environment["PATH"] = (
            f"{self.bin_path}{os.pathsep}{command_environment['PATH']}"
        )
        if environment:
            command_environment.update(environment)
        return subprocess.run(
            ["bash", str(script), *arguments],
            cwd=REPOSITORY_ROOT,
            env=command_environment,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_status_uses_resolved_hostvars_and_reports_current_ports(self) -> None:
        inventory_log = self.temp_path / "inventory.log"
        result = self._run(
            DEPLOY_SCRIPT,
            "--status",
            "--inventory",
            str(self.inventory_path),
            environment={"FAKE_INVENTORY_LOG": str(inventory_log)},
        )

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("192.0.2.100:3309", result.stdout)
        self.assertIn("router-ip:6450", result.stdout)
        self.assertEqual(
            len(inventory_log.read_text(encoding="utf-8").splitlines()),
            1,
        )

    def test_status_fails_when_inventory_values_are_inconsistent(self) -> None:
        result = self._run(
            DEPLOY_SCRIPT,
            "--status",
            "--inventory",
            str(self.inventory_path),
            environment={"FAKE_INVENTORY_MODE": "conflict"},
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("变量值不一致: keepalived_vip", result.stderr)

    def test_health_check_propagates_ansible_failure(self) -> None:
        result = self._run(
            HEALTH_SCRIPT,
            str(self.inventory_path),
            environment={"FAKE_PLAYBOOK_EXIT": "42"},
        )

        self.assertEqual(result.returncode, 42)
        self.assertIn("[1/1]", result.stdout)

    def test_multiple_operations_are_rejected_before_execution(self) -> None:
        result = self._run(
            DEPLOY_SCRIPT,
            "--status",
            "--backup",
            "--inventory",
            str(self.inventory_path),
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("一次只能指定一个操作", result.stdout)

    def test_missing_inventory_is_rejected(self) -> None:
        missing_inventory = self.temp_path / "missing.yml"
        result = self._run(
            DEPLOY_SCRIPT,
            "--status",
            "--inventory",
            str(missing_inventory),
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("inventory 文件不存在", result.stdout)

    def test_rollback_stops_all_tiers_in_safe_order_and_aggregates_errors(
        self,
    ) -> None:
        ansible_log = self.temp_path / "ansible.log"
        result = self._run(
            DEPLOY_SCRIPT,
            "--rollback",
            "--inventory",
            str(self.inventory_path),
            environment={
                "FAKE_ANSIBLE_LOG": str(ansible_log),
                "FAKE_ANSIBLE_FAIL_SERVICE": "keepalived",
            },
        )

        self.assertNotEqual(result.returncode, 0)
        calls = ansible_log.read_text(encoding="utf-8").splitlines()
        self.assertEqual(len(calls), 3)
        self.assertIn("name=keepalived", calls[0])
        self.assertIn("name=haproxy", calls[1])
        self.assertIn("name=mysqlrouter", calls[2])
        self.assertIn("回滚未完整执行", result.stdout)

    def test_mysql_shrink_does_not_run_full_health_with_stale_inventory(
        self,
    ) -> None:
        playbook_log = self.temp_path / "playbook.log"
        result = self._run(
            DEPLOY_SCRIPT,
            "--scale-mysql-remove",
            "--target",
            "mysql-node3",
            "--inventory",
            str(self.inventory_path),
            environment={"FAKE_PLAYBOOK_LOG": str(playbook_log)},
        )

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = playbook_log.read_text(encoding="utf-8").splitlines()
        self.assertEqual(len(calls), 2)
        self.assertIn("playbooks/preflight-ha.yml", calls[0])
        self.assertIn("playbooks/shrink-mysql.yml", calls[1])
        self.assertNotIn("playbooks/health-check-ha.yml", "\n".join(calls))


if __name__ == "__main__":
    unittest.main()
