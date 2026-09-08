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

from prepare import initialize


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
        self.env = dict(os.environ, TMPDIR=str(self.root / 'tmp'),
                        DOCKER_CONFIG=str(self.root / 'config/docker'), LIMA_WORKDIR='/lab')
        if 'metadata' in self.manifest:
            metadata = Path(self.manifest['metadata'])
            if not metadata.exists() and (self.root / 'runtime/metadata').exists():
                shutil.copytree(self.root / 'runtime/metadata', metadata, symlinks=True)
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
        destination = self.root / 'runtime/metadata'
        if destination.exists():
            shutil.rmtree(destination)
        shutil.copytree(self.env['LIMA_HOME'], destination, symlinks=True,
                        ignore=shutil.ignore_patterns('*.sock', '*.pid'))

    def hosts(self):
        compose = yaml.safe_load((self.root / 'config/compose.yml').read_text())
        # Installed RPMs and /etc live in writable container layers. Never recreate.
        existing = self.docker('ps', '-a', '--format', '{{.Names}}').splitlines()
        if any(n.startswith('mysql-ha-lab-') for n in existing):
            raise ValueError('Containers exist: use docker start, not hosts')
        for role, tag in (('node', 'rocky9'), ('controller', 'py313')):
            print(self.docker('build', '-t', f'mysql-ha-lab/{role}:{tag}', f'/lab/config/{role}-image'))
        print(self.docker('compose', '-f', '/lab/config/compose.yml', 'up', '-d'))
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
            lines.append(spec['networks']['labnet']['ipv4_address'] + ' ' + ' '.join(key.split()[:2]))
        (self.root / 'secrets/known_hosts').write_text('\n'.join(lines) + '\n')
        print(self.docker('exec', 'mysql-ha-lab-controller', 'ansible', 'all',
                          '-i', '/lab/config/hosts.local.yml', '-m', 'ping'))
        (self.root / 'reports/images.json').write_text(self.docker('image', 'inspect',
            'mysql-ha-lab/node:rocky9', 'mysql-ha-lab/controller:py313'))
        (self.root / 'reports/docker-version.json').write_text(self.docker('version', '--format', '{{json .}}'))

    def deploy(self, args):
        # Inherit the existing operator CLI and its failures; no alternate SQL deployment.
        return self.docker('exec', '-i', 'mysql-ha-lab-controller', 'bash', 'scripts/deploy_dedicated_routers.sh',
            '-i', '/lab/config/hosts.local.yml', '-e', '@inventory/group_vars/all.yml',
            '-e', '@/lab/config/overrides.yml', '-e', '@/lab/secrets/runtime.yml',
            '--skip-kernel-optimization', *args)

    def stop(self):
        if self.lima('list', 'mysql-ha', '--format', '{{.Status}}').strip() != 'Stopped':
            names = self.docker('ps', '--format', '{{.Names}}').splitlines()
            names = [n for n in names if n.startswith('mysql-ha-lab-')]
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
    parser.add_argument('action', choices=['init', 'vm-create', 'start', 'hosts', 'deploy', 'docker', 'stop'])
    parser.add_argument('args', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.action == 'init':
        initialize(args.root, args.ref)
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
