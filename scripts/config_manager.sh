#!/bin/bash
# 配置管理只改变 mysql_hardware_profile；兼容 macOS Bash 3.2。
set -euo pipefail
repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 - "$repository_root" "$@" <<'PY'
import argparse
import datetime
import json
import os
from pathlib import Path
import re
import sys
import tempfile
import uuid

try:
    import yaml
except ImportError:
    raise SystemExit('请激活项目 Python 环境并安装 requirements.txt')

root = Path(sys.argv.pop(1))
path = root / 'inventory/group_vars/all.yml'
backups = path.parent / 'backups'
parser = argparse.ArgumentParser(description='从唯一配置源列出、验证和切换硬件档位')
actions = parser.add_mutually_exclusive_group(required=True)
for action in ('list', 'current', 'backup', 'validate'):
    actions.add_argument('--' + action, action='store_true')
actions.add_argument('--switch', metavar='PROFILE')
actions.add_argument('--restore', metavar='BACKUP', help='只恢复备份中的硬件档位，保留其他当前配置')
args = parser.parse_args()


def validate(text):
    data = yaml.safe_load(text)
    required = {'mysql_version', 'mysql_hardware_profile', 'mysql_config_profiles',
                'mysql_max_connections', 'mysql_innodb_buffer_pool_size'}
    if not isinstance(data, dict) or not required.issubset(data):
        raise ValueError('缺少必需配置字段')
    profiles = data['mysql_config_profiles']
    if not isinstance(profiles, dict) or not isinstance(data['mysql_hardware_profile'], str) or data['mysql_hardware_profile'] not in profiles:
        raise ValueError('当前硬件档位不存在')
    keys = set(re.findall(r'mysql_config_profiles\[mysql_hardware_profile\]\.([a-z_]+)', text))
    if not keys:
        raise ValueError('未找到硬件档位与运行参数的绑定')
    for name, profile in profiles.items():
        if not isinstance(profile, dict) or not keys.issubset(profile):
            raise ValueError('硬件档位缺少运行参数: ' + str(name))
        connections = profile.get('max_connections')
        if type(connections) is not int or connections < 1:
            raise ValueError('max_connections 必须为正整数: ' + str(name))
    return data


def backup(text):
    backups.mkdir(mode=0o700, exist_ok=True)
    name = 'all-backup-' + datetime.datetime.now().strftime('%Y%m%d_%H%M%S') + '-' + uuid.uuid4().hex[:8] + '.yml'
    destination = backups / name
    with os.fdopen(os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w', encoding='utf-8') as stream:
        stream.write(text)
    print('配置备份: ' + str(destination))


try:
    text = path.read_text(encoding='utf-8')
    data = validate(text)
    if args.list:
        for name in data['mysql_config_profiles']:
            print(name + ('（仅模拟）' if name == 'simulation_minimal' else ''))
    elif args.current:
        selected = data['mysql_hardware_profile']
        print('硬件档位: ' + selected)
        print('MySQL连接数: ' + str(data['mysql_config_profiles'][selected]['max_connections']))
        print('Router连接数: ' + str(data['mysql_router_4c8g_optimized']['max_total_connections']))
    elif args.validate:
        print('配置验证通过')
    elif args.backup:
        backup(text)
    else:
        target = args.switch
        if args.restore:
            if Path(args.restore).name != args.restore:
                raise ValueError('恢复参数必须是 backups/ 下的文件名')
            saved = backups / args.restore
            if saved.is_symlink() or not saved.is_file():
                raise ValueError('备份必须是本地普通文件')
            target = validate(saved.read_text())['mysql_hardware_profile']
        target = {'8c32g-optimized': 'optimized_8c32g', 'original-10k': 'original_10k'}.get(target, target)
        if target not in data['mysql_config_profiles']:
            raise ValueError('未知硬件档位')
        updated, count = re.subn(r'^mysql_hardware_profile:[^\n]*$',
            lambda match: 'mysql_hardware_profile: ' + json.dumps(target), text, flags=re.M)
        if count != 1:
            raise ValueError('必须存在唯一的顶层 mysql_hardware_profile')
        validate(updated)
        if target == data['mysql_hardware_profile']:
            print('档位未变化')
        else:
            backup(text)
            descriptor, staging = tempfile.mkstemp(prefix='.profile-', dir=path.parent)
            try:
                with os.fdopen(descriptor, 'w', encoding='utf-8') as stream:
                    stream.write(updated)
                    stream.flush()
                    os.fsync(stream.fileno())
                os.chmod(staging, path.stat().st_mode & 0o777)
                os.replace(staging, path)
            finally:
                if os.path.exists(staging):
                    os.unlink(staging)
            print('已切换硬件档位: ' + target)
            print('请使用本地 inventory 和 Vault，通过 --apply-config 在维护窗口应用。')
except (OSError, ValueError, KeyError, yaml.YAMLError) as error:
    # YAML errors may include configuration content; avoid printing secret-bearing snippets.
    print('配置操作失败，请检查字段、档位和文件权限。' if isinstance(error, yaml.YAMLError)
          else str(error), file=sys.stderr)
    raise SystemExit(1)
PY
