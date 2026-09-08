"""Offline checks for lab generation and protection of existing local data."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('lab_prepare', ROOT / 'tests/lab/prepare.py')
prepare = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(prepare)


class LabPrepareTests(unittest.TestCase):
    def test_generated_lab_is_private_bounded_and_uses_canonical_source(self):
        (ROOT / 'tmp').mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=ROOT / 'tmp') as directory:
            root = Path(directory) / 'run'
            prepare.initialize(root, 'HEAD')
            compose = yaml.safe_load((root / 'config/compose.yml').read_text())
            self.assertEqual(len(compose['services']), 8)
            self.assertLessEqual(sum(float(v['cpus']) for v in compose['services'].values()), 6)
            for service in compose['services'].values():
                self.assertNotIn('ports', service)
                self.assertEqual(service['mem_limit'], service['memswap_limit'])
                self.assertNotIn('docker.sock', str(service.get('volumes', [])))
            self.assertEqual((root.stat().st_mode & 0o777), 0o700)
            self.assertEqual(((root / 'secrets/runtime.yml').stat().st_mode & 0o777), 0o600)
            self.assertEqual((root / 'source/requirements.txt').read_bytes(),
                             (root / 'config/controller-image/requirements.txt').read_bytes())
            credentials = yaml.safe_load((root / 'secrets/runtime.yml').read_text())
            for name in ('config/compose.yml', 'config/hosts.local.yml', 'config/overrides.yml', 'manifest.json'):
                for password in credentials.values():
                    self.assertNotIn(password, (root / name).read_text())
            before = (root / 'secrets/runtime.yml').read_bytes()
            with self.assertRaises(ValueError):
                prepare.initialize(root, 'HEAD')
            self.assertEqual(before, (root / 'secrets/runtime.yml').read_bytes())
            manifest = json.loads((root / 'manifest.json').read_text())
            self.assertRegex(manifest['source_sha'], r'^[a-f0-9]{40}$')

    def test_output_outside_ignored_workspace_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(ValueError):
                prepare.initialize(Path(directory) / 'lab', 'HEAD')
            self.assertFalse((Path(directory) / 'lab').exists())

    def test_snapshot_copy_failure_preserves_last_complete_metadata(self):
        import sys
        from unittest.mock import patch
        sys.path.insert(0, str(ROOT / 'tests/lab'))
        try:
            from lab import Lab
        finally:
            sys.path.pop(0)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            (root / 'runtime').mkdir()
            disk = root / 'runtime/disk'
            disk.touch()
            metadata = root / 'live'
            (metadata / 'mysql-ha').mkdir(parents=True)
            (metadata / '.lab-owner').write_text(str(root))
            (metadata / 'mysql-ha/lima.yaml').write_text('cpus: 6\n')
            (metadata / 'mysql-ha/disk').symlink_to(disk)
            lab = Lab.__new__(Lab)
            lab.root, lab.env = root, {'LIMA_HOME': str(metadata)}
            lab.save_metadata()
            expected = (root / 'runtime/metadata/mysql-ha/lima.yaml').read_bytes()
            with patch('lab.shutil.copytree', side_effect=OSError('simulated disk full')):
                with self.assertRaises(OSError):
                    lab.save_metadata()
            self.assertEqual((root / 'runtime/metadata/mysql-ha/lima.yaml').read_bytes(), expected)
            (metadata / 'mysql-ha/lima.yaml').write_text('cpus: 4\n')
            lab.save_metadata()
            self.assertEqual((root / 'runtime/metadata-previous/mysql-ha/lima.yaml').read_bytes(), expected)
            self.assertEqual((root / 'runtime/metadata/mysql-ha/disk').resolve(), disk)
