"""Generate a private lab workspace; never write credentials into tracked files."""
from pathlib import Path
import hashlib
import json
import secrets
import shutil
import subprocess
import os
import stat
import uuid
import ipaddress
import re
import copy

import yaml

REPO = Path(__file__).resolve().parents[2]
TEMPLATES = Path(__file__).resolve().parent


TOPOLOGIES = ('dedicated', 'colocated', 'mixed', 'three-entry')


def initialize(root: Path, ref: str, topology: str = 'dedicated') -> None:
    if topology not in TOPOLOGIES:
        raise ValueError('Unknown lab topology')
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
        'mysql_root_password', 'mysql_cluster_password', 'mysql_replication_password', 'lab_app_password')}
    credentials['keepalived_auth_pass'] = secrets.token_hex(4)
    write_yaml(root / 'secrets/runtime.yml', credentials)
    (root / 'secrets/runtime.yml').chmod(0o600)
    (root / 'secrets/known_hosts').touch(mode=0o600)
    probe_dir = root / 'config/probe'
    probe_dir.mkdir()
    for name in ('probe.py', 'probe_guard.py', 'verify_ledger.py'):
        shutil.copy(TEMPLATES / name, probe_dir / name)
    for name in ('node', 'controller'):
        destination = root / 'config' / (name + '-image')
        destination.mkdir()
        shutil.copy(TEMPLATES / (name + '.Dockerfile'), destination / 'Dockerfile')
    shutil.copy(root / 'secrets/id_ed25519.pub', root / 'config/node-image/authorized_keys')
    for src, dest in (('requirements.txt', 'requirements.txt'), ('collections/requirements.yml', 'collections.yml')):
        shutil.copy(root / 'source' / src, root / 'config/controller-image' / dest)
    topology_file = root / 'source/examples/topologies' / (topology + '.yml')
    topology_source = 'snapshot'
    if not topology_file.exists():
        # A current fixture can exercise an older release without modifying it.
        topology_file = REPO / 'examples/topologies' / (topology + '.yml')
        topology_source = 'current-harness'
    inventory, compose = build_topology(yaml.safe_load(topology_file.read_text()), topology)
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
        'topology': topology, 'topology_source': topology_source,
        'topology_sha256': hashlib.sha256(topology_file.read_bytes()).hexdigest(),
        'lima_version': '2.2.0', 'engine_version': '29.8.0',
        'source_digest': source_digest(root / 'source'),
        'template_sha256': hashlib.sha256((TEMPLATES / 'lima.yaml').read_bytes()).hexdigest(),
        'image_template_sha256': {name: hashlib.sha256((TEMPLATES / name).read_bytes()).hexdigest()
                                  for name in ('node.Dockerfile', 'controller.Dockerfile')},
        'probe_sha256': {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                         for path in sorted(probe_dir.glob('*.py'))},
    }, indent=2) + '\n')
    print('Generated private lab for source ' + sha)



def build_topology(inventory: dict, topology: str) -> tuple[dict, dict]:
    """Map canonical example hosts onto an isolated network and bounded resources."""
    if topology not in TOPOLOGIES:
        raise ValueError('Unknown lab topology')
    inventory = copy.deepcopy(inventory)
    inventory['all']['vars'] = {
        'ansible_connection': 'ssh', 'ansible_user': 'root',
        'ansible_python_interpreter': '/usr/bin/python3',
        'ansible_ssh_private_key_file': '/lab/secrets/id_ed25519',
        'ansible_ssh_common_args': '-o StrictHostKeyChecking=yes -o UserKnownHostsFile=/lab/secrets/known_hosts',
    }
    hosts = inventory['all']['hosts']
    groups = inventory['all']['children']
    def validate_groups(group):
        if set(group) - {'hosts', 'children'}:
            raise ValueError('Fixture group variables are not allowed')
        for name, values in group.get('hosts', {}).items():
            if name not in hosts or values:
                raise ValueError('Fixture groups must only reference declared hosts')
        for child in group.get('children', {}).values():
            validate_groups(child)
    for group in groups.values():
        validate_groups(group)
    routers = set(groups['mysql_router']['hosts'])
    lbs = set(groups['haproxy_lb']['hosts'])
    compose = {'name': 'mysql-ha-lab', 'services': {}, 'networks': {
        'labnet': {'name': 'mysql-ha-lab-net', 'ipam': {'config': [{
            'subnet': '172.30.88.0/24', 'aux_addresses': {'vip': '172.30.88.100'}}]}}}, 'volumes': {}}
    addresses = set()
    for host, variables in hosts.items():
        if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_-]*', host):
            raise ValueError('Unsupported fixture host name')
        if set(variables) - {'ansible_host', 'mysql_server_id', 'keepalived_priority', 'keepalived_node_role'}:
            raise ValueError('Unsupported fixture host variables')
        address = ipaddress.ip_address(variables['ansible_host'])
        if address not in ipaddress.ip_network('192.0.2.0/24'):
            raise ValueError('Fixture addresses must use the documentation network')
        suffix = int(address) & 255
        if suffix in (0, 40, 100, 255) or suffix in addresses:
            raise ValueError('Fixture address conflicts with reserved lab addresses')
        addresses.add(suffix)
        ip = '172.30.88.' + str(suffix)
        variables['ansible_host'] = ip
        mysql = 'mysql_server_id' in variables
        memory = 1536 + 512 * (int(host in routers) + int(host in lbs)) if mysql else 512
        cpu = (1.5 if host in routers and host in lbs else 1) if mysql else (0.33 if topology == 'three-entry' else 0.5)
        spec = {
            'image': 'mysql-ha-lab/node:rocky9', 'platform': 'linux/amd64',
            'container_name': 'mysql-ha-lab-' + host, 'hostname': host,
            'privileged': True, 'cgroup': 'private',
            'mem_limit': str(memory) + 'm', 'memswap_limit': str(memory) + 'm',
            'cpus': cpu, 'stop_grace_period': '90s', 'tmpfs': ['/run', '/run/lock', '/tmp'],
            'networks': {'labnet': {'ipv4_address': ip, 'aliases': [host]}},
        }
        if mysql:
            spec['volumes'] = [f'{host}-data:/data', f'{host}-backup:/backup']
            compose['volumes'].update({host + '-data': {}, host + '-backup': {}})
        compose['services'][host] = spec
    compose['services']['controller'] = {
        'image': 'mysql-ha-lab/controller:py313', 'container_name': 'mysql-ha-lab-controller',
        'init': True, 'mem_limit': '1024m', 'memswap_limit': '1024m', 'cpus': 1,
        'environment': {'ANSIBLE_LOG_PATH': '/lab/reports/ansible-live.log', 'ANSIBLE_FORCE_COLOR': '0'},
        'volumes': ['/lab/source:/workspace:ro', '/lab/config:/lab/config:ro',
                    '/lab/secrets:/lab/secrets:ro', '/lab/reports:/lab/reports:rw'],
        'networks': {'labnet': {'ipv4_address': '172.30.88.40'}},
    }
    if sum(float(v['cpus']) for v in compose['services'].values()) > 6:
        raise ValueError('Fixture exceeds the CPU budget')
    if sum(int(v['mem_limit'][:-1]) for v in compose['services'].values()) > 11264:
        raise ValueError('Fixture exceeds the container memory budget')
    return inventory, compose


def write_yaml(path: Path, value: dict) -> None:
    path.write_text(yaml.safe_dump(value, sort_keys=False), encoding='utf-8')


def source_digest(source: Path) -> str:
    """Bind content, relative paths, link targets and modes without following links."""
    digest = hashlib.sha256()
    for path in sorted(source.rglob('*')):
        info = path.lstat()
        record = [path.relative_to(source).as_posix(), stat.S_IMODE(info.st_mode)]
        if path.is_symlink():
            record += ['link', os.readlink(path)]
        elif path.is_file():
            record += ['file', hashlib.sha256(path.read_bytes()).hexdigest()]
        elif path.is_dir():
            record += ['directory']
        else:
            raise ValueError('Unsupported file in source snapshot')
        digest.update((json.dumps(record) + '\n').encode())
    return digest.hexdigest()
