"""Regression checks for actual kernel-run failures found during VM acceptance."""
from pathlib import Path
import os,shutil,subprocess,sys,tempfile,unittest
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

    def test_runtime_parameters_have_one_source_and_drop_obsolete_sysctl(self):
        defaults=yaml.safe_load((ROOT/'inventory/group_vars/all.yml').read_text())
        self.assertNotIn('mysql_kernel_params_stable',self.play['vars'])
        self.assertNotIn('mysql_limits_stable',self.play['vars'])
        self.assertNotIn('kernel.sched_migration_cost_ns',defaults['mysql_kernel_params_stable'])
        self.assertNotIn('kernel.core_pattern',defaults['mysql_kernel_params_stable'])
        migration=next(t for t in self.play['tasks'] if t['name']=='将受管参数从旧 sysctl.conf 迁移到单一配置文件')
        self.assertIn('kernel.sched_migration_cost_ns',migration['loop'])
        self.assertIn('kernel.core_pattern',migration['loop'])

    def test_global_descriptor_limits_never_reduce_existing_capacity(self):
        task=next(t for t in self.play['tasks'] if t['name']=='全局文件句柄上限只提高不降低')
        defaults=yaml.safe_load((ROOT/'inventory/group_vars/all.yml').read_text())
        limits={key:defaults['mysql_kernel_params_stable'][key] for key in ('fs.file-max','fs.nr_open')}
        play={'hosts':'localhost','gather_facts':False,'vars':{
            'file_max':65536,'mysql_kernel_params_stable':limits,
            'kernel_file_limits_current':{'results':[
                {'item':'fs.file-max','stdout':'9223372036854775807'},
                {'item':'fs.nr_open','stdout':'2097152'}]}},
            'tasks':[task,{'ansible.builtin.assert':{'that':[
                "mysql_kernel_params_stable['fs.file-max'] | int == 9223372036854775807",
                "mysql_kernel_params_stable['fs.nr_open'] | int == 2097152"]}}]}
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'limits.yml';path.write_text(yaml.safe_dump([play]))
            result=subprocess.run([ANSIBLE,'-i','localhost,','-c','local',str(path)],capture_output=True,text=True,timeout=30)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_io_apply_check_and_failure_are_observable(self):
        template=Environment(undefined=StrictUndefined).from_string(
            (ROOT/'playbooks/templates/optimize-io-stable.sh.j2').read_text())
        rendered=template.render(mysql_kernel_io_queue_depth_ssd=128,mysql_kernel_io_queue_depth_hdd=64)
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            queue=root/'sys/block/vda/queue';queue.mkdir(parents=True)
            (queue/'scheduler').write_text('none [mq-deadline]\n')
            (queue/'rotational').write_text('1\n')
            (queue/'nr_requests').write_text('128\n')
            bin_dir=root/'bin';bin_dir.mkdir()
            lsblk=bin_dir/'lsblk';lsblk.write_text('#!/bin/sh\nprintf "vda disk 0\\n"\n');lsblk.chmod(0o755)
            script=root/'io.sh'
            # Redirect only the filesystem dependency; execute the rendered shell logic.
            script.write_text(rendered.replace('/sys/block/',str(root/'sys/block')+'/'))
            env={**os.environ,'PATH':str(bin_dir)+os.pathsep+os.environ['PATH']}
            def run(*args):
                return subprocess.run(['bash',str(script),*args],env=env,capture_output=True,text=True,timeout=5)
            before=run('--check')
            self.assertNotEqual(before.returncode,0)
            self.assertEqual((queue/'nr_requests').read_text(),'128\n')
            applied=run();self.assertEqual(applied.returncode,0,applied.stderr)
            self.assertIn('CHANGED:',applied.stdout)
            self.assertEqual(run('--check').returncode,0)
            repeated=run();self.assertEqual(repeated.returncode,0,repeated.stderr)
            self.assertNotIn('CHANGED:',repeated.stdout)
            (queue/'nr_requests').unlink();(queue/'nr_requests').mkdir()
            self.assertNotEqual(run().returncode,0)
            lsblk.write_text('#!/bin/sh\nprintf "vda disk 1\\n"\n')
            skipped=run();self.assertEqual(skipped.returncode,0,skipped.stderr)
            self.assertIn('NOT_APPLICABLE:',skipped.stdout)

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
