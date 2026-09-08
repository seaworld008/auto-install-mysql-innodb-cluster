"""Regressions for failures observed in the Rocky/MySQL 8.4 simulation."""
from pathlib import Path
import unittest
import yaml
from jinja2 import Environment, StrictUndefined

ROOT = Path(__file__).resolve().parents[1]


def tasks(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from tasks(child)
    elif isinstance(value, list):
        for child in value:
            yield from tasks(child)


class RuntimeRegressions(unittest.TestCase):
    def test_user_connection_limit_preserves_small_and_production_profiles(self):
        lines = (ROOT / 'roles/mysql-server/templates/my.cnf.j2').read_text().splitlines()
        template = Environment(undefined=StrictUndefined).from_string('\n'.join(
            line for line in lines if 'reserved_connections' in line))
        for maximum, expected in ((1, 1), (50, 45), (100, 90), (2500, 2400), (10000, 9900)):
            with self.subTest(maximum=maximum):
                self.assertIn(f'max_user_connections = {expected} ', template.render(mysql_max_connections=maximum))

    def test_curl_minimal_is_preserved_on_rhel(self):
        env = Environment(undefined=StrictUndefined)
        for file in ('install-mysql.yml', 'install-router.yml'):
            document = yaml.safe_load((ROOT / 'playbooks' / file).read_text())
            selections = [v for task in tasks(document) for v in task.values()
                          if isinstance(v, list) for v in v
                          if isinstance(v, str) and "'curl-minimal' if" in v]
            self.assertEqual(len(selections), 1)
            template = env.from_string(selections[0])
            self.assertEqual(template.render(ansible_facts={'packages': {'curl-minimal': []}}), 'curl-minimal')
            self.assertEqual(template.render(ansible_facts={'packages': {'curl': []}}), 'curl')

    def test_mysqlsh_auth_and_inline_javascript_survive_yaml_loading(self):
        count = 0
        for file in (ROOT / 'playbooks').glob('*.yml'):
            for task in tasks(yaml.safe_load(file.read_text())):
                command = task.get('ansible.builtin.command', {})
                argv = command.get('argv', []) if isinstance(command, dict) else []
                if not argv or argv[0] != 'mysqlsh':
                    continue
                count += 1
                self.assertEqual(argv[1], '--no-defaults', file.name)
                self.assertIn('--password', argv)
                self.assertIn('--passwords-from-stdin', argv)
                self.assertNotIn('--no-wizard', argv)
                if '--js' in argv:
                    javascript = argv[argv.index('-e') + 1]
                    self.assertTrue(javascript.startswith('shell.options.useWizards = false;'), file.name)
                    self.assertNotRegex(javascript, r'"SELECT[^"\n]*\n')
        self.assertGreater(count, 10)

    def test_account_writes_skip_existing_non_primary_members(self):
        document = yaml.safe_load((ROOT / 'playbooks/install-mysql.yml').read_text())
        found = 0
        env = Environment()
        for task in tasks(document):
            module = task.get('ansible.mysql.mysql_user', {})
            if module.get('host') != '%':
                continue
            found += 1
            self.assertEqual(module['plugin'], 'caching_sha2_password')
            self.assertNotIn('password', module)
            condition = env.compile_expression(task['when'])
            for metadata, primary, expected in ((0, 0, True), (1, 1, True), (1, 0, False)):
                self.assertEqual(condition(mysql_account_writer={'query_result': [[{
                    'metadata_exists': metadata, 'is_primary': primary}]]}), expected)
        self.assertEqual(found, 2)

    def test_bootstrap_does_not_create_destinationless_routing_section(self):
        text = (ROOT / 'playbooks/install-router.yml').read_text()
        self.assertNotIn('--conf-set-option=routing.', text)
        self.assertIn('mysql-shell', text)
        self.assertIn('--strict', text)

    def test_minimal_profile_has_same_keys_as_production(self):
        profiles = yaml.safe_load((ROOT / 'inventory/group_vars/all.yml').read_text())['mysql_config_profiles']
        self.assertEqual(set(profiles['simulation_minimal']), set(profiles['optimized_8c32g']))
        self.assertEqual(profiles['simulation_minimal']['max_connections'], 50)

    def test_operator_status_uses_stdin_auth_without_loading_client_defaults(self):
        import os
        import subprocess
        import tempfile
        with tempfile.TemporaryDirectory() as directory:
            stub = Path(directory) / 'mysqlsh'
            stub.write_text('''#!/usr/bin/env python3
import sys
args = sys.argv[1:]
assert args[0] == '--no-defaults'
assert '--password' in args and '--passwords-from-stdin' in args
assert '--no-wizard' not in args
assert args[-1].startswith('shell.options.useWizards = false; ')
assert sys.stdin.readline().strip() == 'test-input'
assert 'test-input' not in ' '.join(args)
''')
            stub.chmod(0o700)
            result = subprocess.run(['bash', str(ROOT / 'scripts/cluster-status.sh'), '127.0.0.1'],
                env=dict(os.environ, PATH=directory + os.pathsep + os.environ['PATH'],
                         MYSQL_CLUSTER_PASSWORD='test-input'), capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
