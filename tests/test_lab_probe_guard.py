"""Ensure the replayable synthetic probes stay bounded to their lab fixture."""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('probe_guard', ROOT / 'tests/lab/probe_guard.py')
guard = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(guard)


class LabProbeGuardTests(unittest.TestCase):
    def setUp(self):
        self.config = {'all': {'hosts': {'db1': {'ansible_host': '172.30.88.11'}}}}

    def test_local_targets_and_bounded_runs(self):
        guard.validate_target(self.config)
        guard.validate_target(self.config, '172.30.88.11', 'writer-recovery', 1000, 3600)

    def test_external_undeclared_or_invalid_targets_are_rejected(self):
        for host in ('198.51.100.11', '127.0.0.1', '172.30.88.14', '172.30.88.255'):
            with self.subTest(host=host), self.assertRaises(ValueError):
                guard.validate_target(self.config, host=host)
        self.config['all']['hosts']['db1']['ansible_host'] = '192.0.2.11'
        with self.assertRaises(ValueError):
            guard.validate_target(self.config)

    def test_path_escape_and_unbounded_work_are_rejected(self):
        for label in ('../secret', '/tmp/out', 'writer-../../x', 'writer-' + 'x' * 60):
            with self.subTest(label=label), self.assertRaises(ValueError):
                guard.validate_target(self.config, label=label)
        for args in ({'loops': 0}, {'loops': 1001}, {'seconds': 0}, {'seconds': 3601}):
            with self.subTest(args=args), self.assertRaises(ValueError):
                guard.validate_target(self.config, **args)

    def test_old_ledger_cannot_replace_missing_expected_run(self):
        import tempfile
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            old = root / 'writer-old.jsonl'
            old.write_text('{}\n')
            with self.assertRaises(ValueError):
                guard.select_ledgers(root, self.config, ['writer-new'])
            self.assertEqual(guard.select_ledgers(root, self.config, ['writer-old']), [old])
            self.assertEqual(guard.select_ledgers(root, self.config, all_ledgers=True), [old])
            with self.assertRaises(ValueError):
                guard.select_ledgers(root, self.config)
            (root / 'writer-link.jsonl').symlink_to(old)
            with self.assertRaises(ValueError):
                guard.select_ledgers(root, self.config, ['writer-link'])

    def test_changed_probes_are_rejected_before_or_after_execution(self):
        import hashlib
        import sys
        import tempfile
        from unittest.mock import Mock
        sys.path.insert(0, str(ROOT / 'tests/lab'))
        try:
            from lab import Lab
        finally:
            sys.path.pop(0)
        with tempfile.TemporaryDirectory() as directory:
            lab = Lab.__new__(Lab)
            lab.root = Path(directory)
            folder = lab.root / 'config/probe'
            folder.mkdir(parents=True)
            names = ('probe.py', 'probe_guard.py', 'verify_ledger.py')
            for name in names:
                (folder / name).write_text('pass\n')
            lab.manifest = {'probe_sha256': {
                name: hashlib.sha256((folder / name).read_bytes()).hexdigest() for name in names}}
            lab.docker = Mock(return_value='ok')
            self.assertEqual(lab.probe(['ports']), 'ok')
            lab.docker.reset_mock()
            (folder / 'probe.py').write_text('changed\n')
            with self.assertRaises(ValueError):
                lab.probe(['ports'])
            lab.docker.assert_not_called()
            (folder / 'probe.py').write_text('pass\n')
            def change_during_run(*args):
                (folder / 'probe.py').write_text('changed\n')
                return 'not trusted'
            lab.docker.side_effect = change_during_run
            with self.assertRaises(ValueError):
                lab.probe(['ports'])
            lab.docker.assert_called_once()
