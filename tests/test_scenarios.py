"""Offline execution of scenario inventory and selective preflight contracts."""
from copy import deepcopy
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

import yaml
from jinja2 import Environment, StrictUndefined

ROOT = Path(__file__).resolve().parents[1]
ANSIBLE = shutil.which('ansible-playbook') or str(Path(sys.executable).with_name('ansible-playbook'))


class ScenarioTests(unittest.TestCase):
    def run_preflight(self, topology, forced_flags=None, **overrides):
        play = yaml.safe_load((ROOT / 'playbooks/preflight-ha.yml').read_text())[0]
        play['vars_files'] = [str(ROOT / 'inventory/group_vars/all.yml')]
        values = dict(mysql_root_password='fixture-root-value', mysql_cluster_password='fixture-cluster-value',
                      mysql_replication_password='fixture-replication-value', keepalived_auth_pass='fixture',
                      keepalived_vip='172.30.88.100',
                      mysql_group_replication_group_name_override='f1234567-1111-4222-8333-123456789abc')
        values.update(overrides)
        (ROOT / 'tmp').mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=ROOT / 'tmp') as directory:
            temp = Path(directory)
            (temp / 'hosts.yml').write_text(yaml.safe_dump(topology))
            (temp / 'test.yml').write_text(yaml.safe_dump([play]))
            (temp / 'vars.yml').write_text(yaml.safe_dump(values))
            command = [ANSIBLE, '-i', str(temp / 'hosts.yml'), str(temp / 'test.yml'),
                       '-e', '@' + str(temp / 'vars.yml')]
            if forced_flags:
                command += ['-e', forced_flags]
            return subprocess.run(command, cwd=ROOT, text=True,
                                  capture_output=True, timeout=45)

    def test_every_topology_passes_real_local_preflight(self):
        for file in sorted((ROOT / 'examples/topologies').glob('*.yml')):
            with self.subTest(topology=file.name):
                topology = yaml.safe_load(file.read_text())
                result = self.run_preflight(topology)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_duplicate_role_address_and_lb_priority_fail(self):
        baseline = yaml.safe_load((ROOT / 'examples/topologies/three-entry.yml').read_text())
        addresses = deepcopy(baseline)
        addresses['all']['hosts']['router3']['ansible_host'] = addresses['all']['hosts']['router1']['ansible_host']
        result = self.run_preflight(addresses)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('同一部署地址', result.stdout)
        priorities = deepcopy(baseline)
        priorities['all']['hosts']['lb3']['keepalived_priority'] = 150
        result = self.run_preflight(priorities)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('优先级必须', result.stdout)

    def test_haproxy_scope_does_not_require_vrrp_but_full_does(self):
        topology = yaml.safe_load((ROOT / 'examples/topologies/dedicated.yml').read_text())
        overrides = dict(keepalived_auth_pass='CHANGE_ME', keepalived_vip='192.0.2.100')
        result = self.run_preflight(topology, preflight_require_keepalived=False, **overrides)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotEqual(self.run_preflight(topology, **overrides).returncode, 0)
        forced = self.run_preflight(topology, preflight_require_keepalived=False,
            forced_flags='preflight_require_router=true preflight_require_haproxy=true preflight_require_keepalived=true',
            **overrides)
        self.assertNotEqual(forced.returncode, 0)

    def test_three_routers_render_into_each_haproxy_backend(self):
        template = (ROOT / 'roles/haproxy/templates/haproxy.cfg.j2').read_text()
        data = yaml.safe_load((ROOT / 'inventory/group_vars/all.yml').read_text())
        hosts = yaml.safe_load((ROOT / 'examples/topologies/three-entry.yml').read_text())['all']['hosts']
        data.update(groups={'mysql_router': ['router1', 'router2', 'router3']}, hostvars={
            name: dict(values, ansible_default_ipv4={'address': values['ansible_host']})
            for name, values in hosts.items()})
        text = Environment(undefined=StrictUndefined).from_string(template).render(**data)
        for router in ('router1', 'router2', 'router3'):
            self.assertEqual(text.count('server ' + router + ' '), 3)

    def test_kernel_backup_copies_outside_source_and_does_not_ignore_errors(self):
        play = yaml.safe_load((ROOT / 'playbooks/kernel-optimization-stable.yml').read_text())[0]
        copy = next(t for t in play['tasks'] if t['name'] == '备份已有内核配置（失败则停止）')
        self.assertNotIn('ignore_errors', copy)
        defaults = yaml.safe_load((ROOT / 'inventory/group_vars/all.yml').read_text())
        self.assertTrue(defaults['mysql_kernel_backup_root'].startswith('/var/backups/'))
        with tempfile.TemporaryDirectory(dir=ROOT / 'tmp') as directory:
            temp = Path(directory)
            source = temp / 'sysctl.d'
            source.mkdir()
            (source / 'settings.conf').write_text('fixture-content')
            task = deepcopy(copy)
            task['loop'] = [{'item': str(source), 'stat': {'exists': True, 'isdir': True}}]
            test_play = [{'hosts': 'localhost', 'connection': 'local', 'gather_facts': False,
                          'vars': {'backup_dir': str(temp / 'backup')}, 'tasks': [
                {'ansible.builtin.file': {'path': str(temp / 'backup'), 'state': 'directory', 'mode': '0700'}}, task]}]
            path = temp / 'test.yml'
            path.write_text(yaml.safe_dump(test_play))
            result = subprocess.run([ANSIBLE, '-i', 'localhost,', str(path)], cwd=ROOT,
                                    capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual((temp / 'backup/sysctl.d/settings.conf').read_text(), 'fixture-content')

    def test_unsafe_kernel_backup_path_fails_before_any_write(self):
        play = yaml.safe_load((ROOT / 'playbooks/kernel-optimization-stable.yml').read_text())[0]
        guard = next(t for t in play['tasks'] if t['name'] == '检查内核备份根目录')
        for value in ('/var/backups/test;echo injected', '/var/backups/with space', '/var/backups/test\nextra'):
            with self.subTest(value=value), tempfile.TemporaryDirectory(dir=ROOT / 'tmp') as directory:
                temp = Path(directory)
                marker = temp / 'unexpected-write'
                test_play = [{'hosts': 'localhost', 'connection': 'local', 'gather_facts': False,
                              'vars': {'mysql_kernel_backup_root': value}, 'tasks': [guard,
                    {'ansible.builtin.copy': {'dest': str(marker), 'content': 'must not run'}}]}]
                path = temp / 'test.yml'
                path.write_text(yaml.safe_dump(test_play))
                result = subprocess.run([ANSIBLE, '-i', 'localhost,', str(path)], cwd=ROOT,
                                        capture_output=True, text=True, timeout=30)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(marker.exists())

    def test_kernel_backup_symlink_root_is_rejected(self):
        play = yaml.safe_load((ROOT / 'playbooks/kernel-optimization-stable.yml').read_text())[0]
        names = ('检查内核备份根目录状态', '拒绝备份根目录符号链接或普通文件')
        tasks = [next(t for t in play['tasks'] if t['name'] == name) for name in names]
        with tempfile.TemporaryDirectory(dir=ROOT / 'tmp') as directory:
            temp = Path(directory)
            source = temp / 'sysctl.d'
            source.mkdir()
            link = temp / 'backup-root'
            link.symlink_to(source, target_is_directory=True)
            marker = temp / 'unexpected-write'
            probe = [{'hosts': 'localhost', 'connection': 'local', 'gather_facts': False,
                      'vars': {'mysql_kernel_backup_root': str(link)},
                      'tasks': tasks + [{'ansible.builtin.copy': {'dest': str(marker), 'content': 'must not run'}}]}]
            path = temp / 'probe.yml'
            path.write_text(yaml.safe_dump(probe))
            result = subprocess.run([ANSIBLE, '-i', 'localhost,', str(path)], cwd=ROOT,
                                    capture_output=True, text=True, timeout=30)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(marker.exists())

    def test_cross_role_aliases_cannot_claim_colocation(self):
        topology = yaml.safe_load((ROOT / 'examples/topologies/colocated.yml').read_text())
        topology['all']['hosts']['router-alias'] = {'ansible_host': topology['all']['hosts']['db1']['ansible_host']}
        routers = topology['all']['children']['mysql_router']['hosts']
        routers.pop('db1')
        routers['router-alias'] = {}
        result = self.run_preflight(topology)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('共置必须复用同一主机名', result.stdout)
