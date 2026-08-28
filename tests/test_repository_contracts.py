from __future__ import annotations

from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (REPOSITORY_ROOT / relative_path).read_text(encoding="utf-8")


class RepositoryContractTests(unittest.TestCase):
    def test_runtime_ssh_paths_never_disable_host_key_verification(self) -> None:
        runtime_paths = [
            "ansible.cfg",
            "inventory/hosts.yml",
            "inventory/hosts-ha-reference.yml",
            "inventory/hosts-recommended-router.yml",
            "inventory/hosts-with-dedicated-routers.yml",
            "examples/hosts-with-passwords.yml",
            "examples/production-inventory.yml",
            "playbooks/backup.yml",
            "scripts/setup-servers.sh",
        ]
        forbidden = (
            "StrictHostKeyChecking=no",
            "UserKnownHostsFile=/dev/null",
            "host_key_checking = False",
            "ansible_host_key_checking: false",
        )

        for relative_path in runtime_paths:
            content = read(relative_path)
            for value in forbidden:
                with self.subTest(path=relative_path, value=value):
                    self.assertNotIn(value, content)

    def test_supported_shell_scripts_do_not_put_mysql_passwords_in_argv(
        self,
    ) -> None:
        scripts = "\n".join(
            path.read_text(encoding="utf-8")
            for path in sorted((REPOSITORY_ROOT / "scripts").glob("*.sh"))
        )

        self.assertNotRegex(scripts, r":\$\{CLUSTER_PASSWORD\}@")
        self.assertNotRegex(scripts, r"-p\$\{CLUSTER_PASSWORD\}")
        self.assertNotRegex(scripts, r"--password=\$\{CLUSTER_PASSWORD\}")
        self.assertNotIn("[cluster_password]", scripts)
        self.assertIn("MEMBER_CONNECTION_FAILED=1", scripts)
        self.assertIn('validate_endpoint "$CURRENT_PRIMARY"', scripts)

    def test_workflow_actions_are_pinned_to_full_commit_shas(self) -> None:
        workflow_paths = sorted(
            (REPOSITORY_ROOT / ".github" / "workflows").glob("*.yml")
        )
        uses_pattern = re.compile(r"^\s*uses:\s*([^@\s]+)@([^\s#]+)", re.MULTILINE)

        self.assertTrue(workflow_paths)
        for workflow_path in workflow_paths:
            content = workflow_path.read_text(encoding="utf-8")
            for action, revision in uses_pattern.findall(content):
                if action.startswith("./"):
                    continue
                with self.subTest(path=workflow_path.name, action=action):
                    self.assertRegex(revision, r"^[0-9a-f]{40}$")

    def test_dependabot_preserves_supported_dependency_ranges(self) -> None:
        content = read(".github/dependabot.yml")

        self.assertRegex(
            content,
            re.compile(
                r"package-ecosystem: pip.*?"
                r"versioning-strategy: increase-if-necessary",
                re.DOTALL,
            ),
        )

    def test_keepalived_check_enters_fault_without_priority_arithmetic(self) -> None:
        content = read("roles/keepalived/templates/keepalived.conf.j2")
        playbook = read("playbooks/install-keepalived.yml")

        self.assertIn("weight 0", content)
        self.assertIn("fall {{ keepalived_check_fall }}", content)
        self.assertIn("rise {{ keepalived_check_rise }}", content)
        self.assertIn("systemctl is-active --quiet haproxy", content)
        self.assertIn("mode: '0600'", playbook)
        self.assertIn("no_log: true", playbook)

    def test_router_bootstrap_does_not_reuse_a_shared_account(self) -> None:
        content = read("playbooks/install-router.yml")

        self.assertNotRegex(content, r"(?m)^\s*-\s*--account$")
        self.assertIn("--passwords-from-stdin", content)
        self.assertIn("no_log: true", content)

    def test_health_check_is_fail_closed(self) -> None:
        script = read("scripts/health-check-ha.sh")
        playbook = read("playbooks/health-check-ha.yml")

        self.assertNotIn("|| true", script)
        self.assertIn('exec "${health_command[@]}"', script)
        self.assertIn("'ANSIBLE_CLUSTER=OK|'", playbook)
        self.assertIn("'ANSIBLE_SELF_ONLINE=1'", playbook)
        self.assertIn("select('equalto', keepalived_vip)", playbook)

    def test_local_inventory_and_vault_are_ignored_and_generated_locally(self) -> None:
        gitignore = read(".gitignore")
        setup = read("scripts/setup-servers.sh")

        self.assertIn("inventory/hosts.local.yml", gitignore)
        self.assertIn("/inventory/*.local.yml", gitignore)
        self.assertIn("inventory/hosts.local.yml", setup)
        self.assertIn("mysql_group_replication_group_name_override", setup)
        self.assertNotIn("inventory/hosts.yml.bak", setup)

    def test_group_vars_expose_only_effective_runtime_controls(self) -> None:
        content = read("inventory/group_vars/all.yml")

        self.assertNotIn("deployment_features:", content)
        self.assertNotIn("keepalived_enabled:", content)
        self.assertIn("mysql_group_replication_group_name_override", content)
        self.assertIn('deb_sha256: "313ebd0f', content)
        self.assertIn("ssh_known_hosts_file", content)

    def test_placeholder_and_backup_permission_patterns_fail_closed(self) -> None:
        preflight = read("playbooks/preflight-ha.yml")
        backup = read("playbooks/backup.yml")
        placeholder_match = re.search(
            r'credential_placeholder_pattern: "([^"]+)"',
            preflight,
        )

        self.assertIsNotNone(placeholder_match)
        placeholder_pattern = re.compile(placeholder_match.group(1))
        for placeholder in (
            "",
            "CHANGE_ME_ROOT_PASSWORD",
            "REPLACE_IN_ENCRYPTED_VAULT",
            "ENCRYPTED_VALUE",
            "ENCRYPT",
            "your_password_1",
            "router_password_2",
        ):
            with self.subTest(placeholder=placeholder):
                self.assertRegex(placeholder, placeholder_pattern)
        self.assertNotRegex("valid-S3cret!", placeholder_pattern)

        mode_pattern = re.compile(r"^0[0-7][0145][0145]$")
        self.assertRegex("0600", mode_pattern)
        self.assertRegex("0644", mode_pattern)
        self.assertNotRegex("0664", mode_pattern)
        self.assertNotRegex("0666", mode_pattern)
        self.assertIn("backup_ssh_known_hosts.stat.mode is match", backup)
        self.assertIn("hosts: all\n  gather_facts: false", backup)
        self.assertIn("ansible.builtin.meta: end_host", backup)
        self.assertLess(
            backup.index("ansible.builtin.meta: end_host"),
            backup.index("ansible.builtin.setup:"),
        )
        self.assertIn(
            "mysql_cluster_name is match('^[A-Za-z0-9][A-Za-z0-9._-]*$')",
            backup,
        )
        self.assertIn(
            "inventory_hostname is match('^[A-Za-z0-9][A-Za-z0-9._-]*$')",
            backup,
        )

    def test_preflight_scopes_python_gate_and_validates_ipv4_octets(self) -> None:
        content = read("playbooks/preflight-ha.yml")

        self.assertIn("'mysql_cluster:mysql_router:haproxy_lb'", content)
        self.assertIn("'mysql_cluster:mysql_router'", content)
        self.assertIn("else 'mysql_cluster'", content)
        self.assertIn("/usr/bin/python3 python3", content)
        self.assertIn("25[0-5]|2[0-4][0-9]", content)
        self.assertIn("keepalived_vip is not match('^(?:0|127)", content)

    def test_custom_mysql_paths_cover_apparmor_and_selinux(self) -> None:
        content = read("playbooks/install-mysql.yml")

        self.assertIn("semanage fcontext", content)
        self.assertIn("setype: mysqld_db_t", content)
        self.assertIn("setype: mysqld_log_t", content)
        self.assertIn("restorecon", content)
        self.assertIn("/etc/apparmor.d/local/usr.sbin.mysqld", content)

    def test_redhat_root_initialization_is_idempotent_and_escapes_sql(self) -> None:
        content = read("playbooks/install-mysql.yml")

        self.assertIn("mysql_desired_root_probe", content)
        self.assertIn("mysql_desired_root_probe.rc | default(1) != 0", content)
        self.assertIn(
            """replace('\\\\', '\\\\\\\\') | replace(\"'\", \"''\")""",
            content,
        )
        self.assertIn(
            "mysql_temp_password.stdout | to_json(ensure_ascii=False)",
            content,
        )


if __name__ == "__main__":
    unittest.main()
