"""Prepared artifacts must not retain compressed pages that can revert preparation."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import yaml

from tests.test_ansible_safety import ANSIBLE

ROOT = Path(__file__).resolve().parents[1]


class BackupStateTests(unittest.TestCase):
    def test_compressed_prepare_produces_unambiguous_restorable_artifact(self):
        play = yaml.safe_load((ROOT / 'playbooks/backup.yml').read_text())[1]
        names = {'prepare 前解压 XtraBackup 文件', '可选执行 XtraBackup prepare',
                 '读取物理备份实际检查点', '核对物理备份准备状态', '统计物理备份保留的压缩文件',
                 '已准备备份不能保留可覆盖准备结果的压缩副本', '生成备份清单'}
        tasks = [task for task in play['tasks'] if task['name'] in names]
        self.assertEqual(len(tasks), 7)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            backup = root / 'backup'; backup.mkdir()
            (backup / 'table.ibd.zst').write_bytes(b'RAW')
            fake = root / 'xb.py'
            fake.write_text('''from pathlib import Path
import sys
args=sys.argv[1:]
root=Path(next(x.split('=',1)[1] for x in args if x.startswith('--target-dir=')))
if '--decompress' in args:
    for path in root.glob('*.zst'):
        path.with_suffix('').write_bytes(path.read_bytes())
        if '--remove-original' in args: path.unlink()
elif '--prepare' in args:
    path=root/'table.ibd'
    path.write_bytes(path.read_bytes()+b'-PREPARED')
    (root/'xtrabackup_checkpoints').write_text('backup_type = full-prepared\\n')
''')
            for task in tasks:
                command = task.get('ansible.builtin.command', {})
                if command.get('argv', [None])[0] == 'xtrabackup':
                    command['argv'][:1] = [sys.executable, str(fake)]
            variables = {
                'backup_config': {'method': 'xtrabackup', 'type': 'local', 'create_manifest': True,
                    'logical_tool': 'unused', 'xtrabackup': {
                        'parallel': 1, 'compress': True, 'prepare': True, 'use_memory': '128M'}},
                'xtrabackup_target_dir': str(backup), 'backup_manifest_path': str(root / 'manifest.txt'),
                'backup_run_root': str(root), 'backup_timestamp': 'fixture',
                'mysql_cluster_name': 'fixture', 'mysql_port': 3306, 'xtrabackup_package_name': 'fixture-xb',
            }
            path = root / 'test.yml'
            path.write_text(yaml.safe_dump([{'hosts': 'localhost', 'gather_facts': False,
                'vars': variables, 'tasks': tasks}], allow_unicode=True))
            result = subprocess.run([ANSIBLE, '-i', 'localhost,', '-c', 'local', str(path)],
                                    capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual((backup / 'table.ibd').read_bytes(), b'RAW-PREPARED')
            self.assertFalse((backup / 'table.ibd.zst').exists())
            subprocess.run([sys.executable, str(fake), '--decompress', '--target-dir=' + str(backup)], check=True)
            self.assertEqual((backup / 'table.ibd').read_bytes(), b'RAW-PREPARED')
            manifest = (root / 'manifest.txt').read_text()
            self.assertIn('xtrabackup_state=full-prepared', manifest)
            self.assertIn('xtrabackup_compressed_files=0', manifest)
