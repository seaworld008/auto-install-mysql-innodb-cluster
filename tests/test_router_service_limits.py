"""Router descriptor budgeting and restart decisions, without host service changes."""
from pathlib import Path
import subprocess
import tempfile
import unittest

import yaml

from tests.test_ansible_safety import ANSIBLE

ROOT = Path(__file__).resolve().parents[1]


class RouterServiceLimitTests(unittest.TestCase):
    def run_play(self, variables, tasks):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'limits.yml'
            path.write_text(yaml.safe_dump([{
                'hosts': 'localhost', 'gather_facts': False,
                'vars': variables, 'tasks': tasks,
            }], allow_unicode=True))
            return subprocess.run(
                [ANSIBLE, '-i', 'localhost,', '-c', 'local', str(path)],
                capture_output=True, text=True, timeout=30,
            )

    def test_budget_covers_frontend_private_backends_and_idle_pool(self):
        play = yaml.safe_load((ROOT / 'playbooks/install-router.yml').read_text())[0]
        defaults = yaml.safe_load((ROOT / 'inventory/group_vars/all.yml').read_text())
        tasks = [task for task in play['tasks'] if task['name'] in (
            '验证 Router 文件句柄目标', '要求内核支持 Router 文件句柄目标')]
        self.assertEqual(len(tasks), 2)
        for clients, idle, ceiling, override, expected in (
            (120, 0, 1048576, None, True), (30000, 0, 1048576, None, True),
            (120, 64, 1048576, None, True), (120, 0, 1024, None, False),
            (120, 0, 1048576, 1024, False), (0, 0, 1048576, None, False),
        ):
            variables = {
                'mysql_router_max_total_connections': clients,
                'mysql_router_max_idle_server_connections': idle,
                'mysql_router_nofile_limit': override if override is not None else defaults['mysql_router_nofile_limit'],
                'mysqlrouter_kernel_file_limits': {'results': [
                    {'item': 'fs.nr_open', 'stdout': str(ceiling)},
                    {'item': 'fs.file-max', 'stdout': str(ceiling)},
                ]},
            }
            result = self.run_play(variables, tasks)
            self.assertEqual(result.returncode == 0, expected, result.stdout + result.stderr)

    def test_unit_changes_and_live_process_drift_trigger_restart(self):
        play = yaml.safe_load((ROOT / 'playbooks/install-router.yml').read_text())[0]
        decide = next(task for task in play['tasks'] if task['name'] == '计算 Router 重启需求')
        start = next(task for task in play['tasks'] if task['name'] == '启动并启用MySQL Router服务')
        for actual, unit_changed, expected in ((1384, False, 'started'), (1024, False, 'restarted'),
                                               (65535, False, 'restarted'), (1384, True, 'restarted')):
            variables = {
                'mysqlrouter_pre_restart_pid': {'stdout': '123'},
                'mysqlrouter_running_nofile': [[str(actual), str(actual)]],
                'mysqlrouter_systemd_nofile': {'stdout': '1384'},
                'mysqlrouter_systemd_nofile_soft': {'stdout': '1384'},
                'router_bootstrap': {'changed': False},
                'mysqlrouter_config_update': {'changed': False},
                'mysqlrouter_service_update': {'changed': unit_changed},
                'resolved_service_state': start['systemd']['state'],
            }
            result = self.run_play(variables, [decide, {'ansible.builtin.assert': {
                'that': f"resolved_service_state == '{expected}'"}}])
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
