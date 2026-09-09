from pathlib import Path
import json
import shutil
import subprocess
import unittest
import yaml
from jinja2 import Environment

ROOT = Path(__file__).resolve().parents[1]
UUID = 'a1b2c3d4-1111-4222-8333-123456789abc'


@unittest.skipUnless(shutil.which('node'), 'JavaScript runtime unavailable')
class ClusterIdentityTests(unittest.TestCase):
    def script(self, file, task_name):
        plays = yaml.safe_load((ROOT / file).read_text())
        task = next(t for p in plays for t in p.get('tasks', []) if t['name'] == task_name and 'ansible.builtin.command' in t)
        argv = task['ansible.builtin.command']['argv']
        return Environment().from_string(argv[argv.index('-e') + 1]).render(
            mysql_cluster_name='testCluster', mysql_group_replication_group_name=UUID)

    def test_creation_passes_configured_uuid_to_adminapi(self):
        script = self.script('playbooks/configure-cluster.yml', '创建 InnoDB Cluster')
        result = subprocess.check_output(['node', '-e',
            'var shell={options:{}}; var dba={createCluster:(name,options)=>console.log(JSON.stringify(options))};' + script], text=True)
        self.assertEqual(json.loads(result), {'gtidSetIsComplete': True, 'groupName': UUID})

    def test_existing_member_and_health_detect_identity_mismatch(self):
        for file, task in (('playbooks/configure-cluster.yml', '判断实例是否已是在线集群成员'),
                           ('playbooks/health-check-ha.yml', '查询本机 Group Replication 成员状态')):
            script = self.script(file, task)
            for actual, expected in ((UUID.upper(), '1'), ('different', '0')):
                prelude = 'var shell={options:{}}; var print=console.log; var session={runSql:(sql)=>({fetchOne:()=>sql.includes("@@GLOBAL")?[' + json.dumps(actual) + ']:[1]})};'
                output = subprocess.check_output(['node', '-e', prelude + script], text=True)
                self.assertIn('ANSIBLE_GROUP_MATCH=' + expected, output)
