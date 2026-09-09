"""Verify every acknowledged synthetic write; report uncertain commits separately."""
import argparse, json, pymysql
from probe_guard import load_lab, select_ledgers
from pathlib import Path
parser = argparse.ArgumentParser(description=__doc__)
selection = parser.add_mutually_exclusive_group(required=True)
selection.add_argument('--label', action='append', help='Expected writer label; may be repeated')
selection.add_argument('--all', action='store_true', help='Explicitly audit all existing ledgers')
args = parser.parse_args()
config, secret = load_lab()
paths = select_ledgers(Path('/lab/reports'), config, args.label, args.all)
c = pymysql.connect(host='172.30.88.100', port=3307, user='lab_app', password=secret['lab_app_password'], autocommit=True, charset='utf8mb4', connect_timeout=5, read_timeout=20)
reports = []
failures = 0
for path in paths:
    rows = [json.loads(x) for x in path.read_text().splitlines()]
    if not rows:
        raise ValueError('Empty writer ledger cannot prove successful traffic')
    ack = [r for r in rows if r['ack']]
    found = {}
    if not ack:
        raise ValueError('Ledger contains no acknowledged writes')
    with c.cursor() as q:
        for start in range(0, len(rows), 200):
            ids = [r['id'] for r in rows[start:start + 200]]
            if ids:
                q.execute('SELECT id,payload FROM ha_lab.events WHERE id IN (' + ','.join(['%s'] * len(ids)) + ')', ids)
                found.update(q.fetchall())
    bad = [r['id'] for r in ack if found.get(r['id']) != r['payload']]
    failures += len(bad)
    reports.append({'ledger': path.name, 'attempts': len(rows), 'acknowledged': len(ack), 'failed_attempts': len(rows) - len(ack), 'acknowledged_missing_or_changed': len(bad), 'unacknowledged_present': sum((not r['ack'] and r['id'] in found for r in rows))})
if not reports:
    raise ValueError('No writer ledgers found; run a synthetic writer first')
c.close()
print(json.dumps({'failures': failures, 'reports': reports}, indent=2))
raise SystemExit(bool(failures))
