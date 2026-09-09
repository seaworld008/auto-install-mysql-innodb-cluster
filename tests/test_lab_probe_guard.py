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
