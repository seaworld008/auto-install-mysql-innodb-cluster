"""Real inventory selection guards must fail before remote mutations."""
from pathlib import Path
import copy
import subprocess
import tempfile
import unittest

import yaml

from tests.test_ansible_safety import ANSIBLE

ROOT = Path(__file__).resolve().parents[1]
INVENTORY = {'all': {'hosts': {
    **{f'db{i}': {'ansible_host': f'192.0.2.{10+i}'} for i in range(1, 5)},
    'lb1': {'ansible_host': '192.0.2.31'},
}, 'children': {
    'mysql_cluster': {'children': {
        'mysql_primary': {'hosts': {'db1': {}}},
        'mysql_secondary': {'hosts': {'db2': {}, 'db3': {}, 'db4': {}}},
    }},
    'new_mysql': {'hosts': {'db4': {}}},
    'empty_backup': {'hosts': {}},
    'foreign_backup': {'hosts': {'lb1': {}}},
    'duplicate_backup': {'hosts': {'db1': {}, 'db2': {}}},
}}}


class OperationSelectorTests(unittest.TestCase):
    def run_tasks(self, tasks, variables, inventory=INVENTORY):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'hosts.yml').write_text(yaml.safe_dump(inventory))
            (root / 'test.yml').write_text(yaml.safe_dump([{
                'hosts': 'localhost', 'gather_facts': False,
                'vars': variables, 'tasks': tasks,
            }], allow_unicode=True))
            return subprocess.run(
                [ANSIBLE, '-i', str(root / 'hosts.yml'), str(root / 'test.yml')],
                capture_output=True, text=True, timeout=30,
            )

    def test_scale_target_must_be_one_secondary_in_the_configured_allowlist(self):
        play = yaml.safe_load((ROOT / 'playbooks/preflight-ha.yml').read_text())[0]
        guard = next(task for task in play['tasks'] if task['name'] == '在安装前验证 MySQL 扩容目标归属')
        for pattern, group, expected in (
            ('db4', 'mysql_secondary', True), ('db1', 'mysql_secondary', False),
            ('db2:db4', 'mysql_secondary', False), ('absent', 'mysql_secondary', False),
            ('db4', 'new_mysql', True), ('db2', 'new_mysql', False), ('db4', 'absent', False),
        ):
            result = self.run_tasks([guard], {
                'preflight_scale_limit': pattern, 'preflight_read_only': False,
                'scale_policy': {'mysql_scale_target_group': group},
            })
            self.assertEqual(result.returncode == 0, expected, result.stdout + result.stderr)

    def test_backup_group_supports_multiple_members_but_rejects_empty_foreign_and_aliases(self):
        play = yaml.safe_load((ROOT / 'playbooks/backup.yml').read_text())[0]
        names = {'要求备份执行组非空且仅包含集群成员', '初始化备份源地址列表',
                 '收集备份源地址', '拒绝通过多个别名重复备份同一主机'}
        tasks = [task for task in play['tasks'] if task['name'] in names]
        for group, expected in (('new_mysql', True), ('mysql_secondary', True),
                                ('empty_backup', False), ('foreign_backup', False), ('absent', False)):
            result = self.run_tasks(tasks, {'backup_config': {'run_on_host_group': group}})
            self.assertEqual(result.returncode == 0, expected, result.stdout + result.stderr)
        aliased = copy.deepcopy(INVENTORY)
        aliased['all']['hosts']['db2']['ansible_host'] = '192.0.2.11'
        result = self.run_tasks(tasks, {'backup_config': {'run_on_host_group': 'duplicate_backup'}}, aliased)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
