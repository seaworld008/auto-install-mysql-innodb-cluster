"""Execute safety gates locally; never connect to inventory example hosts."""

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[1]
ANSIBLE = shutil.which("ansible-playbook") or str(Path(sys.executable).with_name("ansible-playbook"))


class AnsibleSafetyTests(unittest.TestCase):
    def test_shrink_management_connection_survives_removing_inventory_primary(self):
        play = yaml.safe_load((ROOT / "playbooks/shrink-mysql.yml").read_text())[0]
        task = next(t for t in play["tasks"] if t["name"] == "选择摘除操作执行节点")
        with tempfile.TemporaryDirectory() as temporary:
            inventory = Path(temporary) / "hosts.yml"
            inventory.write_text(yaml.safe_dump({"all": {"children": {
                "mysql_cluster": {"hosts": {"manager": {}, "survivor": {}}},
                "mysql_primary": {"hosts": {"manager": {}}},
            }}}))
            test_play = {
                "hosts": "localhost", "gather_facts": False,
                "vars": {"mysql_shrink_target": "manager", "mysql_shrink_target_is_primary": False},
                "tasks": [task, {"ansible.builtin.assert": {
                    "that": "mysql_shrink_management_host == 'survivor'"
                }}],
            }
            path = Path(temporary) / "test.yml"
            path.write_text(yaml.safe_dump([test_play]))
            result = subprocess.run(
                [ANSIBLE, "-i", str(inventory), str(path)], cwd=ROOT,
                capture_output=True, text=True, timeout=30,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_delegated_add_instance_keeps_secondary_endpoint(self):
        play = yaml.safe_load((ROOT / "playbooks/configure-cluster.yml").read_text())[2]
        with tempfile.TemporaryDirectory() as temporary:
            inventory = Path(temporary) / "hosts.yml"
            inventory.write_text(yaml.safe_dump({"all": {"vars": {
                "ansible_connection": "local", "mysql_port": 3306,
            }, "children": {
                "mysql_primary": {"hosts": {"manager": {"ansible_host": "192.0.2.1"}}},
                "mysql_secondary": {"hosts": {"joining": {"ansible_host": "192.0.2.2", "mysql_port": 3310}}},
            }}}))
            play["gather_facts"] = False
            play["become"] = False
            play["tasks"] = [{
                "ansible.builtin.assert": {"that": "mysql_instance_address == '192.0.2.2:3310'"},
                "delegate_to": "{{ mysql_primary_host }}",
            }]
            path = Path(temporary) / "test.yml"
            path.write_text(yaml.safe_dump([play]))
            result = subprocess.run(
                [ANSIBLE, "-i", str(inventory), str(path)], cwd=ROOT,
                capture_output=True, text=True, timeout=30,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_one_failed_node_prevents_following_operations(self):
        play = yaml.safe_load((ROOT / "playbooks/preflight-ha.yml").read_text())[1]
        play["hosts"] = "all"
        play["tasks"] = [
            {"ansible.builtin.assert": {"that": "inventory_hostname != 'rejected'"}},
            {"ansible.builtin.debug": {"msg": "UNSAFE_CONTINUATION"}},
        ]
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "probe.yml"
            path.write_text(yaml.safe_dump([play]))
            result = subprocess.run(
                [ANSIBLE, "-i", "rejected,healthy,", "-c", "local", str(path)],
                cwd=ROOT, capture_output=True, text=True, timeout=30,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn("UNSAFE_CONTINUATION", result.stdout + result.stderr)

    def test_failed_preflight_prevents_later_plays_on_other_hosts(self):
        for filename in ("preflight-ha.yml", "backup.yml", "shrink-mysql.yml"):
            with self.subTest(playbook=filename), tempfile.TemporaryDirectory() as temporary:
                plays = yaml.safe_load((ROOT / "playbooks" / filename).read_text())
                gate = plays[0]
                # Execute the real first guard with deliberately invalid defaults.
                gate["tasks"] = gate["tasks"][:1]
                later = {
                    "name": "Must never execute after rejected input",
                    "hosts": "probe",
                    "gather_facts": False,
                    "tasks": [{"ansible.builtin.debug": {"msg": "UNSAFE_CONTINUATION"}}],
                }
                path = Path(temporary) / "probe.yml"
                path.write_text(yaml.safe_dump([gate, later], allow_unicode=True))
                result = subprocess.run(
                    [ANSIBLE, "-i", "probe,", "-c", "local", str(path),
                     "-e", "@inventory/group_vars/all.yml"],
                    cwd=ROOT, capture_output=True, text=True,
                    env={**os.environ, "ANSIBLE_NOCOLOR": "1"}, timeout=30,
                )
                output = result.stdout + result.stderr
                self.assertNotEqual(result.returncode, 0, output)
                self.assertIn("failed=1", output)
                self.assertNotIn("UNSAFE_CONTINUATION", output)


if __name__ == "__main__":
    unittest.main()
