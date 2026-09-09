"""Advertised-address safety for new and already-registered cluster members."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import yaml
from jinja2 import Environment, StrictUndefined

ROOT = Path(__file__).resolve().parents[1]


class ReportHostTests(unittest.TestCase):
    def setUp(self):
        (ROOT / 'tmp').mkdir(exist_ok=True)
        self.tasks = yaml.safe_load((ROOT / 'playbooks/install-mysql.yml').read_text())[0]['tasks']

    def run_cases(self, cases):
        names = ['验证 MySQL 通告地址格式', '拒绝在普通部署中改变已有成员通告地址',
                 '保留已有成员通告地址或采用新实例配置', '验证最终通告地址不含配置控制字符']
        tasks = [next(t for t in self.tasks if t['name'] == name) for name in names]
        plays = []
        for requested, registered, reported, expected in cases:
            plays.append({'hosts': 'localhost', 'gather_facts': False,
                          'vars': {'ansible_facts': {'nodename':'new-node'}, 'mysql_report_host': requested, 'mysql_has_cluster_metadata': registered,
                                   'mysql_existing_report_address': {'query_result': [[{'report_host': reported, 'hostname': 'db1'}]]},
                                   'expected': expected},
                          'tasks': tasks + [{'ansible.builtin.assert': {'that': 'mysql_effective_report_host == expected'}}]})
        with tempfile.TemporaryDirectory(dir=ROOT / 'tmp') as directory:
            path = Path(directory) / 'test.yml'
            path.write_text(yaml.safe_dump(plays,allow_unicode=True))
            return subprocess.run([str(Path(sys.executable).with_name('ansible-playbook')), '-i', 'localhost,', '-c', 'local', str(path)],
                                  capture_output=True,text=True,timeout=30)

    def test_new_address_and_existing_address_preservation(self):
        result = self.run_cases([('', False, '', 'new-node'), ('192.0.2.11', False, '', '192.0.2.11'),
                                 ('', True, '192.0.2.11', '192.0.2.11'),
                                 ('192.0.2.11', True, '192.0.2.11', '192.0.2.11'),
                                 ('', True, '', 'db1'), ('', True, None, 'db1'), ('db1', True, None, 'db1')])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_existing_canonical_address_cannot_be_reassigned(self):
        result = self.run_cases([('192.0.2.11', True, '', '192.0.2.11')])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('普通部署不会迁移已注册的成员地址', result.stdout)

    def test_configuration_control_characters_and_port_are_rejected(self):
        for address in ['db1\nskip-grant-tables', '192.0.2.11:3306', 'db1\n']:
            result = self.run_cases([(address, False, '', address)])
            self.assertNotEqual(result.returncode, 0, address)
            self.assertIn('mysql_report_host 必须为空', result.stdout)

    def test_template_default_is_empty_and_explicit_address_is_emitted(self):
        text = (ROOT / 'roles/mysql-server/templates/my.cnf.j2').read_text()
        block = text[text.index('{% set report_host'):text.index('mysqlx_port =')]
        template = Environment(undefined=StrictUndefined, trim_blocks=True).from_string(block)
        self.assertEqual(template.render(mysql_report_host=''), '')
        self.assertEqual(template.render(mysql_report_host='192.0.2.11'), 'report_host = 192.0.2.11\n')
        self.assertEqual(template.render(mysql_report_host='', mysql_effective_report_host='db1.example.test'),
                         'report_host = db1.example.test\n')

    def test_address_read_does_not_depend_on_account_awaiting_reconciliation(self):
        task = next(t for t in self.tasks if t['name'] == '读取已有成员的通告地址')
        query = task['ansible.mysql.mysql_query']
        self.assertEqual(query['login_user'], 'root')
        self.assertEqual(query['login_password'], '{{ mysql_root_password }}')
        self.assertEqual(query['config_file'], '')
        self.assertIn('mysql_existing_socket.stat.issock', query['login_unix_socket'])
        self.assertNotIn('mysql_cluster_password', str(query))
        self.assertTrue(task['no_log'])
        self.assertLess(self.tasks.index(task),
                        next(i for i,t in enumerate(self.tasks) if t['name']=='创建集群管理用户'))
        readiness = next(t for t in self.tasks if t['name'] == '等待现有集群成员恢复 ONLINE')
        self.assertEqual(readiness['ansible.mysql.mysql_query']['login_user'], 'root')
        self.assertEqual(readiness['ansible.mysql.mysql_query']['login_password'], '{{ mysql_root_password }}')
        self.assertEqual(readiness['ansible.mysql.mysql_query']['config_file'], '')

    def test_inventory_override_survives_group_vars_precedence(self):
        with tempfile.TemporaryDirectory(dir=ROOT / 'tmp') as directory:
            root = Path(directory)
            (root / 'group_vars').symlink_to(ROOT / 'inventory/group_vars', target_is_directory=True)
            inventory = {'all': {'hosts': {'db1': {'ansible_host': '192.0.2.11'}},
                                 'vars': {'ansible_connection': 'local',
                                          'mysql_report_host_override': '{{ ansible_host }}'}}}
            (root / 'hosts.yml').write_text(yaml.safe_dump(inventory))
            (root / 'check.yml').write_text(yaml.safe_dump([
                {'hosts': 'all', 'gather_facts': False,
                 'tasks': [{'ansible.builtin.assert': {'that': 'mysql_report_host == ansible_host'}}]}]))
            result = subprocess.run([str(Path(sys.executable).with_name('ansible-playbook')),
                                     '-i', str(root / 'hosts.yml'), str(root / 'check.yml')],
                                    capture_output=True,text=True,timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
