"""Exercise service-capacity guards with Ansible, without touching host services."""
import base64
from pathlib import Path
import subprocess
import tempfile
import unittest

import yaml

from tests.test_ansible_safety import ANSIBLE

ROOT = Path(__file__).resolve().parents[1]


class MysqlServiceLimitTests(unittest.TestCase):
    def test_interrupted_update_converges_once_and_healthy_process_is_not_restarted(self):
        play = yaml.safe_load((ROOT / 'playbooks/install-mysql.yml').read_text())[0]
        drift = next(task for task in play['tasks'] if task['name'] == '让已有进程收敛到文件句柄目标')
        with tempfile.TemporaryDirectory() as directory:
            for target, actual, expected_restarts in (
                (65535, '10000', 1), (65535, '65535', 0),
                (65535, '100000', 1), (4096, '65535', 1),
            ):
                test_play = {
                    'hosts': 'localhost', 'gather_facts': False,
                    'vars': {'mysql_open_files_limit': target,
                             'mysql_systemd_nofile': {'stdout': str(target)},
                             'mysql_systemd_nofile_soft': {'stdout': str(target)},
                             'mysql_pre_restart_pid': {'stdout': '123'},
                             'mysql_running_nofile': [[actual, actual]]},
                    'tasks': [drift, drift, {'ansible.builtin.meta': 'flush_handlers'},
                              {'ansible.builtin.assert': {'that':
                               f'restart_count | default(0) | int == {expected_restarts}'}}],
                    'handlers': [{'name': 'restart mysql', 'ansible.builtin.set_fact': {
                        'restart_count': '{{ (restart_count | default(0) | int) + 1 }}'}}],
                }
                path = Path(directory) / 'restart.yml'
                path.write_text(yaml.safe_dump([test_play], allow_unicode=True))
                result = subprocess.run(
                    [ANSIBLE, '-i', 'localhost,', '-c', 'local', str(path)],
                    capture_output=True, text=True, timeout=30,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_rejects_unusable_limits_before_claiming_capacity(self):
        play = yaml.safe_load((ROOT / 'playbooks/install-mysql.yml').read_text())[0]
        names = {
            '验证 MySQL 文件句柄目标', '要求内核支持 MySQL 文件句柄目标',
            '在重启前拒绝冲突的 systemd 文件句柄配置', '核对 MySQL 实际文件句柄容量',
        }
        tasks = [task for task in play['tasks'] if task['name'] in names]
        self.assertEqual(len(tasks), 4)
        cases = [(value, 1048576, value, value, True) for value in (4096, 65535, 100000)]
        cases += [
            (-1, 1048576, 4096, 4096, False),
            (True, 1048576, 4096, 4096, False),
            ('1.5', 1048576, 4096, 4096, False),
            (65535, 32768, 65535, 65535, False),
            (65535, 1048576, 10000, 65535, False),
            (65535, 1048576, 2097152, 65535, False),
            (65535, 1048576, 65535, 10000, False),
            (16384, 1048576, (65535, 4096), 65535, False),
            (16384, 1048576, (65535, 32768), (32768, 65535), True),
        ]
        with tempfile.TemporaryDirectory() as directory:
            for target, kernel, effective, process, expected in cases:
                with self.subTest(target=target, kernel=kernel, effective=effective, process=process):
                    hard, soft = effective if isinstance(effective, tuple) else (effective, effective)
                    actual_soft, actual_hard = process if isinstance(process, tuple) else (process, process)
                    content = f'Max open files            {actual_soft}                {actual_hard}                files\n'
                    variables = {
                        'mysql_open_files_limit': target,
                        'mysql_kernel_file_limits': {'results': [
                            {'item': 'fs.nr_open', 'stdout': str(kernel)},
                            {'item': 'fs.file-max', 'stdout': str(kernel)},
                        ]},
                        'mysql_systemd_nofile': {'stdout': str(hard)},
                        'mysql_systemd_nofile_soft': {'stdout': str(soft)},
                        'mysql_process_limits': {'content': base64.b64encode(content.encode()).decode()},
                    }
                    path = Path(directory) / 'guards.yml'
                    path.write_text(yaml.safe_dump([{
                        'hosts': 'localhost', 'gather_facts': False,
                        'vars': variables, 'tasks': tasks,
                    }], allow_unicode=True))
                    result = subprocess.run(
                        [ANSIBLE, '-i', 'localhost,', '-c', 'local', str(path)],
                        capture_output=True, text=True, timeout=30,
                    )
                    self.assertEqual(result.returncode == 0, expected, result.stdout + result.stderr)
