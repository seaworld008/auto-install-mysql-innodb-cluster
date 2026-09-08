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
