"""Generate a private lab workspace; never write credentials into tracked files."""
from pathlib import Path
import hashlib
import json
import secrets
import shutil
import subprocess
import uuid

import yaml

REPO = Path(__file__).resolve().parents[2]
TEMPLATES = Path(__file__).resolve().parent


def initialize(root: Path, ref: str) -> None:
    root = root.resolve()
    if not root.is_relative_to((REPO / 'tmp').resolve()):
        raise ValueError('Lab output must be inside this repository tmp/ directory')
    if root.exists():
        raise ValueError('Output already exists; refusing to replace data or credentials')
    sha = subprocess.check_output(['git', '-C', str(REPO), 'rev-parse', ref + '^{commit}'], text=True).strip()
    root.mkdir(parents=True, mode=0o700)
    for name in ('config', 'secrets', 'source', 'reports', 'cache', 'runtime', 'tmp'):
        (root / name).mkdir(mode=0o700)
    archive = root / 'source.tar'
    subprocess.run(['git', '-C', str(REPO), 'archive', '--output', str(archive), sha], check=True)
    subprocess.run(['tar', '-xf', str(archive), '-C', str(root / 'source')], check=True)
    archive.unlink()
    subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-C', 'isolated-mysql-lab',
                    '-f', str(root / 'secrets/id_ed25519')], check=True)
    credentials = {k: 'Aa9!' + secrets.token_hex(24) for k in (
        'mysql_root_password', 'mysql_cluster_password', 'mysql_replication_password')}
    credentials['keepalived_auth_pass'] = secrets.token_hex(4)
    write_yaml(root / 'secrets/runtime.yml', credentials)
    (root / 'secrets/runtime.yml').chmod(0o600)
    (root / 'secrets/known_hosts').touch(mode=0o600)
    for name in ('node', 'controller'):
        destination = root / 'config' / (name + '-image')
        destination.mkdir()
        shutil.copy(TEMPLATES / (name + '.Dockerfile'), destination / 'Dockerfile')
    shutil.copy(root / 'secrets/id_ed25519.pub', root / 'config/node-image/authorized_keys')
    for src, dest in (('requirements.txt', 'requirements.txt'), ('collections/requirements.yml', 'collections.yml')):
        shutil.copy(root / 'source' / src, root / 'config/controller-image' / dest)
    inventory = {'all': {'vars': {
        'ansible_user': 'root', 'ansible_python_interpreter': '/usr/bin/python3',
        'ansible_ssh_private_key_file': '/lab/secrets/id_ed25519',
        'ansible_ssh_common_args': '-o StrictHostKeyChecking=yes -o UserKnownHostsFile=/lab/secrets/known_hosts',
    }, 'children': {}}}
    children = inventory['all']['children']
    children['mysql_cluster'] = {'children': {'mysql_primary': {'hosts': {}}, 'mysql_secondary': {'hosts': {}}}}
    compose = {'name': 'mysql-ha-lab', 'services': {}, 'networks': {
        'labnet': {'name': 'mysql-ha-lab-net', 'ipam': {'config': [{
            'subnet': '172.30.88.0/24', 'aux_addresses': {'vip': '172.30.88.100'}}]}}}, 'volumes': {}}
    for role, count, offset, group in (('mysql', 3, 10, None), ('router', 2, 20, 'mysql_router'), ('lb', 2, 30, 'haproxy_lb')):
        if group:
            children[group] = {'hosts': {}}
        for number in range(1, count + 1):
            service, host, ip = f'{role}{number}', f'{role}-node{number}', f'172.30.88.{offset + number}'
            variables = {'ansible_host': ip}
            if role == 'mysql':
                variables['mysql_server_id'] = number
                target = children['mysql_cluster']['children']['mysql_primary' if number == 1 else 'mysql_secondary']['hosts']
            else:
                target = children[group]['hosts']
            if role == 'lb':
                variables.update(keepalived_node_role='master' if number == 1 else 'backup', keepalived_priority=110 - number * 10)
            target[host] = variables
            memory = '1536m' if role == 'mysql' else '512m'
            compose['services'][service] = {
                'image': 'mysql-ha-lab/node:rocky9', 'platform': 'linux/amd64',
                'container_name': 'mysql-ha-lab-' + service, 'hostname': host,
                'privileged': True, 'cgroup': 'private', 'mem_limit': memory, 'memswap_limit': memory,
                'cpus': 1 if role == 'mysql' else 0.5, 'stop_grace_period': '90s',
                'tmpfs': ['/run', '/run/lock', '/tmp'],
                'networks': {'labnet': {'ipv4_address': ip, 'aliases': [host]}},
            }
            if role == 'mysql':
                compose['services'][service]['volumes'] = [f'{service}-data:/data', f'{service}-backup:/backup']
                compose['volumes'].update({service + '-data': {}, service + '-backup': {}})
    compose['services']['controller'] = {
        'image': 'mysql-ha-lab/controller:py313', 'container_name': 'mysql-ha-lab-controller',
        'mem_limit': '1024m', 'memswap_limit': '1024m', 'cpus': 1,
        'volumes': ['/lab/source:/workspace:ro', '/lab/config:/lab/config:ro',
                    '/lab/secrets:/lab/secrets:ro', '/lab/reports:/lab/reports:rw'],
        'networks': {'labnet': {'ipv4_address': '172.30.88.40'}},
    }
    write_yaml(root / 'config/compose.yml', compose)
    write_yaml(root / 'config/hosts.local.yml', inventory)
    write_yaml(root / 'config/overrides.yml', {
        'mysql_hardware_profile': 'simulation_minimal', 'mysql_router_max_total_connections': 120,
        'mysql_router_route_max_connections': 50, 'haproxy_global_maxconn': 100,
        'keepalived_vip': '172.30.88.100', 'keepalived_interface': 'eth0',
        'mysql_group_replication_group_name_override': str(uuid.uuid4()),
    })
    config = yaml.safe_load((TEMPLATES / 'lima.yaml').read_text())
    config['mounts'][0]['location'] = str(root)
    write_yaml(root / 'config/lima.yaml', config)
    (root / 'manifest.json').write_text(json.dumps({
        'owner': 'mysql-ha-lab-v1', 'root': str(root), 'source_sha': sha,
        'lima_version': '2.2.0', 'engine_version': '29.8.0',
        'template_sha256': hashlib.sha256((TEMPLATES / 'lima.yaml').read_bytes()).hexdigest(),
    }, indent=2) + '\n')
    print('Generated private lab for source ' + sha)


def write_yaml(path: Path, value: dict) -> None:
    path.write_text(yaml.safe_dump(value, sort_keys=False), encoding='utf-8')
