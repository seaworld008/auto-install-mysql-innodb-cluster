from __future__ import annotations

from pathlib import Path
import unittest

import yaml
from jinja2 import Environment, StrictUndefined


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]


class MySQLTemplateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.environment = Environment(undefined=StrictUndefined)

    def test_libaio_package_matches_every_supported_debian_family_release(
        self,
    ) -> None:
        group_vars = yaml.safe_load(
            (REPOSITORY_ROOT / "inventory/group_vars/all.yml").read_text(
                encoding="utf-8"
            )
        )
        playbook = yaml.safe_load(
            (REPOSITORY_ROOT / "playbooks/install-mysql.yml").read_text(
                encoding="utf-8"
            )
        )
        package_template = self.environment.from_string(
            playbook[0]["vars"]["mysql_libaio_package"]
        )
        expected_packages = {
            ("Ubuntu", "jammy"): "libaio1",
            ("Ubuntu", "noble"): "libaio1t64",
            ("Ubuntu", "plucky"): "libaio1t64",
            ("Ubuntu", "questing"): "libaio1t64",
            ("Debian", "bookworm"): "libaio1",
            ("Debian", "trixie"): "libaio1t64",
        }

        supported_releases = {
            **{
                ("Ubuntu", release): expected_packages[("Ubuntu", release)]
                for release in group_vars["mysql_supported_ubuntu_releases"]
            },
            **{
                ("Debian", release): expected_packages[("Debian", release)]
                for release in group_vars["mysql_supported_debian_releases"]
            },
        }
        self.assertEqual(expected_packages, supported_releases)

        for (distribution, release), expected in supported_releases.items():
            with self.subTest(distribution=distribution, release=release):
                rendered = package_template.render(
                    ansible_distribution=distribution,
                    ansible_distribution_release=release,
                ).strip()
                self.assertEqual(expected, rendered)

    def test_table_definition_cache_respects_mysql_minimum(self) -> None:
        variables = yaml.safe_load(
            (REPOSITORY_ROOT / "inventory/group_vars/all.yml").read_text()
        )
        calculation = self.environment.from_string(
            variables["mysql_table_definition_cache"]
        )
        for opened, expected in [(256, 400), (800, 400), (4000, 2000)]:
            with self.subTest(table_open_cache=opened):
                self.assertEqual(
                    int(calculation.render(mysql_table_open_cache=opened)), expected
                )

    def test_group_replication_addresses_render_without_remote_facts(self) -> None:
        template_lines = (
            REPOSITORY_ROOT / "roles/mysql-server/templates/my.cnf.j2"
        ).read_text(encoding="utf-8").splitlines()
        address_template = self.environment.from_string(
            "\n".join(
                line
                for line in template_lines
                if line.startswith("group_replication_local_address")
                or line.startswith("group_replication_group_seeds")
            )
        )

        rendered = address_template.render(
            ansible_host="10.20.0.11",
            inventory_hostname="mysql-1",
            mysql_group_replication_port=33061,
            groups={"mysql_cluster": ["mysql-1", "mysql-2", "mysql-3"]},
            hostvars={
                "mysql-1": {"ansible_host": "10.20.0.11"},
                "mysql-2": {"ansible_host": "10.20.0.12"},
                "mysql-3": {},
            },
        )

        self.assertIn(
            'group_replication_local_address = "10.20.0.11:33061"', rendered
        )
        self.assertIn(
            'group_replication_group_seeds = '
            '"10.20.0.11:33061,10.20.0.12:33061,mysql-3:33061"',
            rendered,
        )

    def test_group_replication_local_address_falls_back_to_inventory_name(
        self,
    ) -> None:
        local_address_line = next(
            line
            for line in (
                REPOSITORY_ROOT / "roles/mysql-server/templates/my.cnf.j2"
            ).read_text(encoding="utf-8").splitlines()
            if line.startswith("group_replication_local_address")
        )

        rendered = self.environment.from_string(local_address_line).render(
            inventory_hostname="mysql-1",
            mysql_group_replication_port=33061,
        )

        self.assertEqual(
            'group_replication_local_address = "mysql-1:33061"', rendered
        )


if __name__ == "__main__":
    unittest.main()
