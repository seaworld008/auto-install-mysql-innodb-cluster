"""Boundary checks for synthetic traffic in the fixed local simulation network."""
import ipaddress
from pathlib import Path
import re

import yaml

VIP = '172.30.88.100'
NETWORK = ipaddress.ip_network('172.30.88.0/24')


def validate_target(config, host=VIP, label='writer-default', loops=20, seconds=60):
    addresses = [entry['ansible_host'] for entry in config['all']['hosts'].values()]
    if not addresses or len(set(addresses)) != len(addresses):
        raise ValueError('Expected distinct local simulation hosts')
    for address in [*addresses, host]:
        parsed = ipaddress.ip_address(address)
        if parsed not in NETWORK or parsed in (NETWORK.network_address, NETWORK.broadcast_address):
            raise ValueError('Synthetic probes only support the local simulation network')
    if host != VIP and host not in addresses:
        raise ValueError('Probe target is not declared in the local inventory')
    if not re.fullmatch(r'writer-[a-z0-9][a-z0-9-]{0,55}', label):
        raise ValueError('Writer label must be a short writer- name without path components')
    if not 1 <= loops <= 1000 or not 1 <= seconds <= 3600:
        raise ValueError('Probe duration or iterations exceed the bounded test range')


def load_lab():
    config = yaml.safe_load(Path('/lab/config/hosts.local.yml').read_text())
    validate_target(config, label='writer-default')
    credentials = yaml.safe_load(Path('/lab/secrets/runtime.yml').read_text())
    for key in ('mysql_cluster_password', 'lab_app_password'):
        if not isinstance(credentials.get(key), str) or len(credentials[key]) < 20:
            raise ValueError('Initialize a private lab with generated test credentials first')
    return config, credentials
