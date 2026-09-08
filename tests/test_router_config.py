import configparser
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

import yaml

from ansible.errors import AnsibleFilterError
from tests.test_ansible_safety import ANSIBLE


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "router_config", ROOT / "playbooks/filter_plugins/mysql_router_config.py"
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

BOOTSTRAP = """[DEFAULT]
keyring_path=/var/lib/mysqlrouter/data/keyring
master_key_path=/var/lib/mysqlrouter/mysqlrouter.key
max_total_connections=100
[metadata_cache:bootstrap]
router_id=42
user=fixture_router_identity
metadata_cluster=prodCluster
[routing:bootstrap_rw]
bind_port=6446
destinations=metadata-cache://prodCluster/?role=PRIMARY
protocol=classic
[routing:bootstrap_ro]
bind_port=6447
destinations=metadata-cache://prodCluster/?role=SECONDARY
protocol=classic
[routing:bootstrap_rw_split]
bind_port=6450
[routing:read_write_split]
bind_port=6450
[http_server]
port=8443
"""


class RouterConfigTests(unittest.TestCase):
    def setUp(self):
        self.settings = {
            "cluster_name": "prodCluster", "max_total_connections": 30000,
            "metadata_read_timeout": 30, "metadata_connect_timeout": 5,
            "rw_port": 7000, "ro_port": 7001, "split_port": 7010,
            "admin_port": 8444, "rw_strategy": "first-available",
            "ro_strategy": "round-robin", "split_strategy": "round-robin",
            "routing": {"max_connections": 15000, "max_connect_errors": 100,
                        "client_connect_timeout": 9, "connect_timeout": 5},
        }

    def test_updates_settings_preserves_identity_and_removes_duplicate_route(self):
        text = module.mysql_router_config(BOOTSTRAP, self.settings)
        parser = configparser.ConfigParser(interpolation=None)
        parser.read_string(text)
        self.assertEqual(parser["metadata_cache:bootstrap"]["router_id"], "42")
        self.assertEqual(parser["metadata_cache:bootstrap"]["user"], "fixture_router_identity")
        self.assertEqual(parser["DEFAULT"]["keyring_path"], "/var/lib/mysqlrouter/data/keyring")
        self.assertEqual(parser["DEFAULT"]["max_total_connections"], "30000")
        self.assertEqual(parser["routing:bootstrap_ro"]["bind_port"], "7001")
        self.assertEqual(parser["routing:bootstrap_rw"]["destinations"],
                         "metadata-cache://prodCluster/?role=PRIMARY")
        self.assertEqual(parser["routing:bootstrap_rw_split"]["bind_port"], "7010")
        self.assertEqual(parser["routing:bootstrap_rw_split"]["access_mode"], "auto")
        self.assertFalse(parser.has_section("routing:read_write_split"))
        self.assertEqual(parser["http_server"]["port"], "8444")
        self.assertEqual(module.mysql_router_config(text, self.settings), text)

    def test_migrates_legacy_split_without_creating_second_listener(self):
        legacy = BOOTSTRAP.replace("[routing:bootstrap_rw_split]\nbind_port=6450\n", "")
        text = module.mysql_router_config(legacy, self.settings)
        self.assertEqual(text.count("[routing:bootstrap_rw_split]"), 1)
        self.assertNotIn("[routing:read_write_split]", text)

    def test_rejects_split_strategy_incompatible_with_metadata_role(self):
        self.settings["split_strategy"] = "round-robin-with-fallback"
        with self.assertRaises(AnsibleFilterError):
            module.mysql_router_config(BOOTSTRAP, self.settings)

    def test_rejects_unknown_or_malformed_config_without_echoing_content(self):
        for text in ("fixture confidential text", "[DEFAULT]\nkeyring_path=fixture\n", BOOTSTRAP + "[routing:bootstrap_rw]\n"):
            with self.subTest(content_type=text[:10]):
                with self.assertRaises(AnsibleFilterError) as error:
                    module.mysql_router_config(text, self.settings)
                self.assertNotIn("fixture", str(error.exception))

    def test_real_ansible_filter_copy_is_idempotent(self):
        play = yaml.safe_load((ROOT / "playbooks/install-router.yml").read_text())[0]
        tasks = [t for t in play["tasks"] if t.get("register") in (
            "mysqlrouter_current_config", "mysqlrouter_config_update"
        )]
        with tempfile.TemporaryDirectory() as temporary:
            config = Path(temporary) / "mysqlrouter.conf"
            config.write_text(BOOTSTRAP)
            tasks[0]["ansible.builtin.slurp"]["src"] = str(config)
            copy = tasks[1]["ansible.builtin.copy"]
            copy["dest"] = str(config)
            del copy["owner"], copy["group"]
            test_play = {
                "hosts": "localhost", "gather_facts": False,
                "vars": play["vars"],
                "tasks": tasks + tasks + [{"ansible.builtin.assert": {
                    "that": "not mysqlrouter_config_update.changed"
                }}],
            }
            path = Path(temporary) / "test.yml"
            path.write_text(yaml.safe_dump([test_play], allow_unicode=True))
            result = subprocess.run(
                [ANSIBLE, "-i", "localhost,", "-c", "local", str(path),
                 "-e", "@inventory/group_vars/all.yml"], cwd=ROOT,
                env={**os.environ, "ANSIBLE_FILTER_PLUGINS": str(ROOT / "playbooks/filter_plugins")},
                capture_output=True, text=True, timeout=40,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("max_total_connections=30000", config.read_text())
            self.assertNotIn("[routing:read_write_split]", config.read_text())
