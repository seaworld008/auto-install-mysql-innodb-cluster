from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
import yaml

ROOT = Path(__file__).resolve().parents[1]


class ConfigManagerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / 'scripts').mkdir()
        (self.root / 'inventory/group_vars').mkdir(parents=True)
        self.script = self.root / 'scripts/config_manager.sh'
        shutil.copy(ROOT / 'scripts/config_manager.sh', self.script)
        self.config = self.root / 'inventory/group_vars/all.yml'
        shutil.copy(ROOT / 'inventory/group_vars/all.yml', self.config)

    def run_manager(self, *args):
        return subprocess.run(['/bin/bash', str(self.script), *args], capture_output=True, text=True,
            env=dict(os.environ, PATH=str(Path(sys.executable).parent) + os.pathsep + os.environ['PATH']))

    def test_lists_all_canonical_profiles_and_reports_router_limit(self):
        result = self.run_manager('--list')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, '')
        for profile in yaml.safe_load(self.config.read_text())['mysql_config_profiles']:
            self.assertIn(profile, result.stdout)
        result = self.run_manager('--current')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Router连接数: 30000', result.stdout)

    def test_switch_changes_only_selector_and_protects_backup(self):
        original = yaml.safe_load(self.config.read_text())
        result = self.run_manager('--switch', 'simulation_minimal')
        self.assertEqual(result.returncode, 0, result.stderr)
        changed = yaml.safe_load(self.config.read_text())
        original['mysql_hardware_profile'] = 'simulation_minimal'
        self.assertEqual(original, changed)
        backups = list(self.config.parent.glob('backups/*.yml'))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.run_manager('--switch', 'simulation_minimal').returncode, 0)
        self.assertEqual(len(list(self.config.parent.glob('backups/*.yml'))), 1)

    def test_invalid_profile_and_incomplete_config_fail_without_writes(self):
        before = self.config.read_bytes()
        self.assertNotEqual(self.run_manager('--switch', 'unknown').returncode, 0)
        self.assertEqual(before, self.config.read_bytes())
        data = yaml.safe_load(before)
        for mutate in (lambda d: d.pop('mysql_version'),
                       lambda d: d.update(mysql_hardware_profile='missing'),
                       lambda d: d['mysql_config_profiles']['simulation_minimal'].pop('max_connections')):
            document = yaml.safe_load(before)
            mutate(document)
            self.config.write_text(yaml.safe_dump(document))
            self.assertNotEqual(self.run_manager('--validate').returncode, 0)
        self.config.write_bytes(before)
        self.assertEqual(self.run_manager('--validate').returncode, 0)

    def test_restore_only_changes_profile_and_rejects_parent_paths(self):
        self.assertEqual(self.run_manager('--switch', 'simulation_minimal').returncode, 0)
        backup = next(self.config.parent.glob('backups/*.yml'))
        data = yaml.safe_load(self.config.read_text())
        data['mysql_port'] = 13306
        self.config.write_text(yaml.safe_dump(data, sort_keys=False))
        result = self.run_manager('--restore', backup.name)
        self.assertEqual(result.returncode, 0, result.stderr)
        restored = yaml.safe_load(self.config.read_text())
        self.assertEqual(restored['mysql_port'], 13306)
        self.assertEqual(restored['mysql_hardware_profile'], 'optimized_8c32g')
        self.assertNotEqual(self.run_manager('--restore', '../all.yml').returncode, 0)
