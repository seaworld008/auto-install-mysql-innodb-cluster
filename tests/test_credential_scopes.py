"""Only require credentials actually consumed by an operation."""
from pathlib import Path
import subprocess
import tempfile
import unittest

import yaml

from tests.test_ansible_safety import ANSIBLE

ROOT = Path(__file__).resolve().parents[1]


class CredentialScopeTests(unittest.TestCase):
    def test_operation_specific_secrets_and_read_only_checks(self):
        play = yaml.safe_load((ROOT / 'playbooks/preflight-ha.yml').read_text())[0]
        names = {'验证凭据检查范围', '检查集群管理密码', '检查 MySQL 安装或物理备份的 root 密码',
                 '检查 MySQL 安装的复制密码', '检查 Keepalived 配置所需的认证口令'}
        tasks = [task for task in play['tasks'] if task['name'] in names]
        self.assertEqual(len(tasks), 5)
        base = dict(play['vars'], mysql_cluster_password='fixture-cluster',
                    mysql_root_password='CHANGE_ME_ROOT_PASSWORD',
                    mysql_replication_password='CHANGE_ME_REPLICATION_PASSWORD',
                    keepalived_auth_pass='CHANGE_ME', preflight_require_keepalived=False,
                    backup_config={'method': 'logical'})
        cases = [
            ({'preflight_credential_scope': 'cluster'}, True),
            ({'preflight_credential_scope': 'install'}, False),
            ({'preflight_credential_scope': 'install', 'mysql_root_password': 'fixture-root'}, False),
            ({'preflight_credential_scope': 'install', 'mysql_root_password': 'fixture-root',
              'mysql_replication_password': 'fixture-replica'}, True),
            ({'preflight_credential_scope': 'cluster', 'mysql_cluster_password': 'CHANGE_ME_CLUSTER_PASSWORD'}, False),
            ({'preflight_credential_scope': 'cluster', 'preflight_require_keepalived': True}, False),
            ({'preflight_credential_scope': 'cluster', 'preflight_require_keepalived': True,
              'keepalived_auth_pass': 'fixture'}, True),
            ({'preflight_credential_scope': 'cluster', 'preflight_require_keepalived': True,
              'preflight_read_only': True}, True),
            ({'preflight_credential_scope': 'backup'}, True),
            ({'preflight_credential_scope': 'backup', 'backup_config': {'method': 'xtrabackup'}}, False),
            ({'preflight_credential_scope': 'backup', 'backup_config': {'method': 'xtrabackup'},
              'mysql_root_password': 'fixture-root'}, True),
            ({'preflight_credential_scope': 'unknown'}, False),
            ({'preflight_credential_scope': 'cluster', 'mysql_cluster_password': None}, False),
            ({'preflight_credential_scope': 'cluster', 'mysql_cluster_password': True}, False),
            ({'preflight_credential_scope': 'cluster', 'mysql_cluster_password': 123456}, False),
        ]
        with tempfile.TemporaryDirectory() as directory:
            for overrides, expected in cases:
                variables = {**base, **overrides}
                if overrides == {'preflight_credential_scope': 'cluster'}:
                    variables.pop('mysql_root_password')
                    variables.pop('mysql_replication_password')
                path = Path(directory) / 'credentials.yml'
                path.write_text(yaml.safe_dump([{
                    'hosts': 'localhost', 'gather_facts': False,
                    'vars': variables, 'tasks': tasks,
                }], allow_unicode=True))
                result = subprocess.run(
                    [ANSIBLE, '-i', 'localhost,', '-c', 'local', str(path)],
                    capture_output=True, text=True, timeout=30,
                )
                self.assertEqual(result.returncode == 0, expected, result.stdout + result.stderr)
