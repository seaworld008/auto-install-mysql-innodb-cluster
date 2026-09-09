#!/usr/bin/env python3
"""Lifecycle for a dedicated local Linux-host simulation (not a deployment flow)."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
import time

import yaml

from prepare import TOPOLOGIES, initialize, source_digest


def run(args, **kwargs):
    return subprocess.run([str(x) for x in args], check=True, **kwargs)


def output(args, **kwargs):
    return run(args, text=True, capture_output=True, **kwargs).stdout


class Lab:
    def __init__(self, root, limactl):
        self.root = root.resolve()
        self.manifest = json.loads((self.root / 'manifest.json').read_text())
        if self.manifest.get('owner') != 'mysql-ha-lab-v1' or self.manifest['root'] != str(self.root):
            raise ValueError('Lab ownership marker does not match this directory')
        self.limactl = limactl
        actual_version = output([limactl, '--version']).strip().split()[-1]
        if actual_version != self.manifest['lima_version']:
            raise ValueError('Lima version differs from this lab manifest')
        self.env = dict(os.environ, TMPDIR=str(self.root / 'tmp'),
                        DOCKER_CONFIG=str(self.root / 'config/docker'), LIMA_WORKDIR='/lab')
        if 'metadata' in self.manifest:
            disk = self.root / 'runtime/disk'
            if disk.is_symlink() or not disk.is_file():
                raise ValueError('Missing regular lab disk; refusing to recreate it')
            metadata = Path(self.manifest['metadata'])
            if not metadata.exists():
                snapshot = self.root / 'runtime/metadata'
                if not snapshot.exists():
                    snapshot = self.root / 'runtime/metadata-previous'
                shutil.copytree(snapshot, metadata, symlinks=True)
            if metadata.is_symlink() or metadata.stat().st_uid != os.getuid():
                raise ValueError('Invalid metadata ownership')
            if (metadata / '.lab-owner').read_text().strip() != str(self.root):
                raise ValueError('Metadata belongs to another lab')
            self.env['LIMA_HOME'] = str(metadata)

    def lima(self, *args, **kwargs):
        if 'LIMA_HOME' not in self.env:
            raise ValueError('Run vm-create first')
        return output([self.limactl, *args], env=self.env, **kwargs)

    def docker(self, *args, **kwargs):
        return self.lima('shell', '--workdir', '/lab', 'mysql-ha', 'sudo', 'docker', *args, **kwargs)

    def vm_create(self):
        if platform.system() != 'Darwin' or platform.machine() != 'arm64':
            raise ValueError('This recipe requires an Apple Silicon Mac with Rosetta installed')
        if 'metadata' in self.manifest:
            raise ValueError('VM already registered; use start, never recreate an existing lab')
        if output([self.limactl, '--version']).strip().split()[-1] != '2.2.0':
            raise ValueError('This tested recipe requires Lima 2.2.0')
        image = yaml.safe_load((self.root / 'config/lima.yaml').read_text())['images'][0]
        cached = self.root / 'cache/ubuntu.img'
        # Download directly to the external workspace, bypassing Lima's macOS cache.
        run(['curl', '--fail', '--location', '--retry', '3', '--output', cached, image['location']])
        with cached.open('rb') as source:
            digest = hashlib.file_digest(source, 'sha256').hexdigest()
        if 'sha256:' + digest != image['digest']:
            raise ValueError('Ubuntu image checksum mismatch')
        disk = self.root / 'runtime/disk'
        if disk.exists():
            raise ValueError('Existing disk found; refusing to overwrite')
        run(['qemu-img', 'convert', '-f', 'qcow2', '-O', 'raw', cached, disk])
        run(['qemu-img', 'resize', '-f', 'raw', disk, '60G'])
        metadata = Path(tempfile.mkdtemp(prefix='mysql-lab-', dir='/tmp'))
        (metadata / '.lab-owner').write_text(str(self.root) + '\n')
        self.env['LIMA_HOME'] = str(metadata)
        self.manifest['metadata'] = str(metadata)
        self.save_manifest()
        # Lima create eagerly copies a disk into LIMA_HOME. Seed its minimal
        # instance metadata instead, validate it, then start against our disk.
        instance = metadata / 'mysql-ha'
        instance.mkdir(mode=0o700)
        shutil.copy(self.root / 'config/lima.yaml', instance / 'lima.yaml')
        (instance / 'lima-version').write_text('2.2.0\n')
        (instance / 'disk').symlink_to(disk)
        print(self.lima('validate', instance / 'lima.yaml'))
        self.save_metadata()
        print('VM prepared with external sparse disk. Run start next.')

    def save_manifest(self):
        (self.root / 'manifest.json').write_text(json.dumps(self.manifest, indent=2) + '\n')

    def save_metadata(self):
        runtime = self.root / 'runtime'
        staged = Path(tempfile.mkdtemp(prefix='metadata-staging-', dir=runtime))
        shutil.copytree(self.env['LIMA_HOME'], staged, symlinks=True,
                        dirs_exist_ok=True, ignore=shutil.ignore_patterns('*.sock', '*.pid'))
        if (staged / '.lab-owner').read_text().strip() != str(self.root):
            raise ValueError('Snapshot ownership mismatch')
        if not (staged / 'mysql-ha/lima.yaml').is_file():
            raise ValueError('Snapshot has no instance configuration')
        disk = staged / 'mysql-ha/disk'
        canonical_disk = self.root / 'runtime/disk'
        if canonical_disk.is_symlink() or not canonical_disk.is_file():
            raise ValueError('Snapshot requires an existing regular lab disk')
        if not disk.is_symlink() or disk.resolve(strict=True) != canonical_disk:
            raise ValueError('Snapshot disk does not point to this lab')
        destination, previous = runtime / 'metadata', runtime / 'metadata-previous'
        # The last complete snapshot survives every failure before promotion.
        if destination.exists():
            if previous.exists():
                shutil.rmtree(previous)
            destination.rename(previous)
        staged.rename(destination)

    def hosts(self):
        compose = yaml.safe_load((self.root / 'config/compose.yml').read_text())
        # Installed RPMs and /etc live in writable container layers. Never recreate.
        existing = self.docker('ps', '-a', '--format', '{{.Names}}').splitlines()
        expected = {spec['container_name'] for spec in compose['services'].values()}
        for name in (n for n in existing if n.startswith('mysql-ha-lab-')):
            if name not in expected:
                raise ValueError('Unknown lab container; reconcile inventory first: ' + name)
            labels = json.loads(self.docker('inspect', '--format', '{{json .Config.Labels}}', name))
            if labels.get('com.docker.compose.project') != compose['name']:
                raise ValueError('Container is not owned by this compose project: ' + name)
        for role, tag in (('node', 'rocky9'), ('controller', 'py313')):
            if not expected.intersection(existing):
                print(self.docker('build', '--platform', 'linux/amd64' if role == 'node' else 'linux/arm64',
                                  '-t', f'mysql-ha-lab/{role}:{tag}', f'/lab/config/{role}-image'))
        print(self.docker('compose', '-f', '/lab/config/compose.yml', 'up', '-d', '--no-recreate'))
        known = dict(line.split(' ', 1) for line in (self.root / 'secrets/known_hosts').read_text().splitlines())
        lines = []
        for service, spec in compose['services'].items():
            if service == 'controller':
                continue
            for attempt in range(60):
                try:
                    self.docker('exec', spec['container_name'], 'systemctl', 'is-active', 'sshd')
                    key = self.docker('exec', spec['container_name'], 'cat', '/etc/ssh/ssh_host_ed25519_key.pub')
                    break
                except subprocess.CalledProcessError:
                    if attempt == 59:
                        raise
                    time.sleep(1)
            address = spec['networks']['labnet']['ipv4_address']
            public_key = ' '.join(key.split()[:2])
            if address in known and known[address] != public_key:
                raise ValueError('Pinned SSH key changed: ' + address)
            lines.append(address + ' ' + public_key)
        (self.root / 'secrets/known_hosts').write_text('\n'.join(lines) + '\n')
        print(self.docker('exec', 'mysql-ha-lab-controller', 'ansible', 'all',
                          '-i', '/lab/config/hosts.local.yml', '-m', 'ping'))
        (self.root / 'reports/images.json').write_text(self.docker('image', 'inspect',
            'mysql-ha-lab/node:rocky9', 'mysql-ha-lab/controller:py313'))
        (self.root / 'reports/docker-version.json').write_text(self.docker('version', '--format', '{{json .}}'))

    def deploy(self, args):
        if source_digest(self.root / 'source') != self.manifest.get('source_digest'):
            raise ValueError('Source snapshot changed; initialize a new lab from the desired commit')
        # Inherit the existing operator CLI and its failures; no alternate SQL deployment.
        return self.docker('exec', '-i', 'mysql-ha-lab-controller', 'bash', 'scripts/deploy_dedicated_routers.sh',
            '-i', '/lab/config/hosts.local.yml', '-e', '@inventory/group_vars/all.yml',
            '-e', '@/lab/config/overrides.yml', '-e', '@/lab/secrets/runtime.yml',
            '--skip-kernel-optimization', *args)

    def verify_probe_files(self):
        expected = self.manifest.get('probe_sha256', {})
        if set(expected) != {'probe.py', 'probe_guard.py', 'verify_ledger.py'}:
            raise ValueError('This lab has no sealed probe set; initialize a new lab')
        directory = self.root / 'config/probe'
        if directory.is_symlink():
            raise ValueError('Probe directory must not be a symlink')
        for name, digest in expected.items():
            path = directory / name
            if path.is_symlink() or not path.is_file():
                raise ValueError('Missing regular probe file: ' + name)
            if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
                raise ValueError('Probe changed since initialization: ' + name)

    def probe(self, args, verify_ledger=False):
        self.verify_probe_files()
        name = 'verify_ledger.py' if verify_ledger else 'probe.py'
        result = self.docker('exec', 'mysql-ha-lab-controller', 'python',
                             '/lab/config/probe/' + name, *args)
        self.verify_probe_files()
        return result

    def stop(self):
        if self.lima('list', 'mysql-ha', '--format', '{{.Status}}').strip() != 'Stopped':
            names = self.docker('ps', '--format', '{{.Names}}').splitlines()
            project = yaml.safe_load((self.root / 'config/compose.yml').read_text())['name']
            for name in names:
                labels = json.loads(self.docker('inspect', '--format', '{{json .Config.Labels}}', name))
                if not name.startswith('mysql-ha-lab-') or labels.get('com.docker.compose.project') != project:
                    raise ValueError('Foreign container in dedicated VM; refusing to stop it: ' + name)
            # The controller has no database to drain. Older saved fixtures used
            # sleep as PID 1, which otherwise consumed the full database timeout.
            controller = 'mysql-ha-lab-controller'
            if controller in names:
                print(self.docker('stop', '--timeout', '10', controller))
                names.remove(controller)
            if names:
                print(self.docker('stop', '--timeout', '90', *names))
            print(self.lima('stop', 'mysql-ha'))
        self.save_metadata()
        print('Stopped; disk, credentials and metadata preserved.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--limactl', default='limactl')
    parser.add_argument('--ref', default='HEAD', help='Committed source revision for init')
    parser.add_argument('--topology', choices=TOPOLOGIES, default='dedicated', help='Canonical topology for a new lab')
    parser.add_argument('action', choices=['init', 'vm-create', 'start', 'hosts', 'deploy',
                                         'probe', 'verify-ledger', 'docker', 'stop'])
    parser.add_argument('args', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.action == 'init':
        initialize(args.root, args.ref, args.topology)
        return
    lab = Lab(args.root, args.limactl)
    extra = args.args[1:] if args.args[:1] == ['--'] else args.args
    if args.action == 'vm-create':
        lab.vm_create()
    elif args.action == 'start':
        print(lab.lima('start', '--tty=false', 'mysql-ha'))
    elif args.action == 'hosts':
        lab.hosts()
    elif args.action == 'deploy':
        print(lab.deploy(extra))
    elif args.action == 'docker':
        print(lab.docker(*extra))
    elif args.action in ('probe', 'verify-ledger'):
        print(lab.probe(extra, verify_ledger=args.action == 'verify-ledger'))
    else:
        lab.stop()


if __name__ == '__main__':
    try:
        main()
    except subprocess.CalledProcessError as error:
        import sys
        print(error.stdout or '', file=sys.stderr)
        print(error.stderr or '', file=sys.stderr)
        raise SystemExit(error.returncode)
