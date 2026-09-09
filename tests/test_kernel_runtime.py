"""Regression checks for actual kernel-run failures found during VM acceptance."""
from pathlib import Path
import shutil,subprocess,sys,tempfile,unittest
import yaml
from jinja2 import Environment, StrictUndefined

ROOT=Path(__file__).resolve().parents[1]
ANSIBLE=shutil.which('ansible-playbook') or str(Path(sys.executable).with_name('ansible-playbook'))

class KernelRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.play=yaml.safe_load((ROOT/'playbooks/kernel-optimization-stable.yml').read_text())[0]

    def test_memory_math_evaluates_with_ansible_native_types(self):
        plays=[]
        for memory,expected in [(2048,1073741824),(32768,20615843021),(262144,68719476736)]:
            variables=dict(self.play['vars'],ansible_memtotal_mb=memory,ansible_processor_vcpus=2)
            plays.append({'hosts':'localhost','gather_facts':False,'vars':variables,'tasks':[
                {'ansible.builtin.assert':{'that':f'shmmax_bytes | int == {expected}'}}]})
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'probe.yml';path.write_text(yaml.safe_dump(plays))
            result=subprocess.run([ANSIBLE,'-i','localhost,','-c','local',str(path)],capture_output=True,text=True,timeout=30)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_sysctl_uses_one_file_and_verifies_runtime_values(self):
        tasks=self.play['tasks']
        template=next(t for t in tasks if t['name']=='创建MySQL稳定内核优化配置文件')
        apply=next(t for t in tasks if t['name']=='应用内核参数')
        self.assertEqual(apply['ansible.posix.sysctl']['sysctl_file'],template['template']['dest'])
        migrate=next(t for t in tasks if t['name']=='将受管参数从旧 sysctl.conf 迁移到单一配置文件')
        self.assertEqual(migrate['ansible.posix.sysctl']['state'],'absent')
        self.assertEqual(migrate['ansible.posix.sysctl']['sysctl_file'],'/etc/sysctl.conf')
        self.assertFalse(migrate['ansible.posix.sysctl']['reload'])
        self.assertTrue(apply['ansible.posix.sysctl']['sysctl_set'])
        self.assertFalse(apply['ansible.posix.sysctl']['reload'])
        self.assertNotIn('ignore_errors',apply)
        self.assertTrue(any(t['name']=='要求运行值与期望内核参数一致' for t in tasks))
        for name in ('启用禁用透明大页服务','启用I/O优化服务'):
            task=next(t for t in tasks if t['name']==name)
            self.assertNotIn('when',task)
            self.assertTrue(task['systemd']['enabled'])

    def test_report_does_not_mistake_available_never_for_selected_never(self):
        env=Environment(undefined=StrictUndefined)
        env.filters['split']=lambda value:str(value).split()
        template=env.from_string((ROOT/'playbooks/templates/optimization-report-stable.txt.j2').read_text())
        context=dict(ansible_date_time={'iso8601':'fixture'},inventory_hostname='node',ansible_distribution='Ubuntu',
            ansible_distribution_version='24.04',ansible_kernel='fixture',cpu_cores=2,total_memory_gb=3,
            script_version='fixture',optimization_level='fixture',backup_dir='/fixture',
            mysql_kernel_params_stable={'net.core.somaxconn':8192,'fs.file-max':65536,'vm.swappiness':0,
                'vm.dirty_ratio':15,'net.ipv4.tcp_congestion_control':'bbr'},
            scheduler_status={'rc':0,'stdout':'vda: mq-deadline'},kernel_units_enabled={'results':[]},
            sysctl_verify={'results':[{'item':{'key':'vm.swappiness','value':0},'stdout':'0','rc':0}]})
        wrong=template.render(**context,thp_status={'rc':0,'stdout':'always [madvise] never'})
        self.assertIn('FAIL: never 未选中',wrong)
        right=template.render(**context,thp_status={'rc':0,'stdout':'always madvise [never]'})
        self.assertIn('PASS: never',right)
        self.assertIn('实际: 0',right)
