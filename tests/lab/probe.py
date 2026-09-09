"""Synthetic application checks. No production installation or cluster management."""
import argparse, hashlib, json, time, uuid, datetime
from pathlib import Path
import pymysql
from probe_guard import load_lab, validate_target
p = argparse.ArgumentParser()
p.add_argument('action', choices=['init', 'signature', 'ports', 'writer', 'identity'])
p.add_argument('--host', default='172.30.88.100')
p.add_argument('--seconds', type=int, default=60)
p.add_argument('--loops', type=int, default=20)
p.add_argument('--label', default='writer-default')
args = p.parse_args()
config, secrets = load_lab()
validate_target(config, args.host, args.label, args.loops, args.seconds)
root = Path('/lab/reports')

def connect(port=3307, admin=False, host=None):
    return pymysql.connect(host=host or args.host, port=port, user='clusteradmin' if admin else 'lab_app', password=secrets['mysql_cluster_password'] if admin else secrets['lab_app_password'], charset='utf8mb4', connect_timeout=5, read_timeout=10, write_timeout=10, autocommit=True)

def dump(value):
    print(json.dumps(value, default=str, ensure_ascii=False))
if args.action == 'init':
    c = connect(admin=True)
    with c.cursor() as cur:
        cur.execute('CREATE DATABASE ha_lab')
        cur.execute('CREATE TABLE ha_lab.events (id VARCHAR(80) PRIMARY KEY, payload VARCHAR(200) NOT NULL) ENGINE=InnoDB')
        cur.executemany('INSERT INTO ha_lab.events VALUES (%s,%s)', [(f'seed-{i:06}', f'synthetic-{i:06}') for i in range(1000)])
        cur.execute('CREATE TABLE ha_lab.type_samples (id INT PRIMARY KEY, txt VARCHAR(200), amount DECIMAL(20,6), created DATETIME(6), raw_data VARBINARY(64), json_data JSON, optional_value VARCHAR(20) NULL) ENGINE=InnoDB')
        cur.executemany('INSERT INTO ha_lab.type_samples VALUES (%s,%s,%s,%s,%s,%s,%s)', [(i, "中文🚀\nquote'" + str(i), '1234567890.123456', '2026-09-10 00:00:00.123456', bytes([0, 1, 255, i]), json.dumps({'n': i, 'text': '恢复验证'}, ensure_ascii=False), None) for i in range(8)])
        cur.execute('CREATE USER %s@%s IDENTIFIED BY %s', ('lab_app', '%', secrets['lab_app_password']))
        cur.execute('GRANT SELECT, INSERT, UPDATE, DELETE ON ha_lab.* TO %s@%s', ('lab_app', '%'))
    c.close()
    dump({'seed_rows': 1000, 'type_rows': 8})
elif args.action == 'signature':
    c = connect()
    result = {}
    with c.cursor() as cur:
        cur.execute('SHOW TABLES FROM ha_lab')
        tables = sorted((row[0] for row in cur.fetchall()))
        for name in tables:
            table = '`' + name.replace('`', '``') + '`'
            cur.execute('SHOW CREATE TABLE ha_lab.' + table)
            ddl = cur.fetchone()[1]
            cur.execute('SELECT * FROM ha_lab.' + table + ' ORDER BY id')
            rows = cur.fetchall()
            result[name] = {'rows': len(rows), 'data_sha256': hashlib.sha256(json.dumps(rows, default=str, ensure_ascii=False, separators=(',', ':')).encode()).hexdigest(), 'ddl_sha256': hashlib.sha256(ddl.encode()).hexdigest()}
    c.close()
    dump(result)
elif args.action == 'identity':
    result = {}
    for host, values in config['all']['hosts'].items():
        if 'mysql_server_id' not in values:
            continue
        c = connect(port=3306, admin=True, host=values['ansible_host'])
        with c.cursor() as cur:
            cur.execute('SELECT @@server_uuid, @@GLOBAL.group_replication_group_name, @@hostname, @@port, @@max_connections, @@wait_timeout')
            result[host] = cur.fetchone()
        c.close()
    dump(result)
elif args.action == 'ports':
    results = []
    failures = 0
    for iteration in range(args.loops):
        for port in [3307, 3308, 3309]:
            c = None
            record = {'iteration': iteration, 'port': port}
            try:
                c = connect({3307: 6446, 3308: 6447, 3309: 6450}[port] if args.host != '172.30.88.100' else port)
                with c.cursor() as cur:
                    cur.execute('SELECT @@hostname,@@read_only,@@super_read_only')
                    record['backend'] = cur.fetchone()
                    if port == 3308:
                        assert record['backend'][2] == 1
                        try:
                            cur.execute('INSERT INTO ha_lab.events VALUES (%s,%s)', ('ro-' + uuid.uuid4().hex, 'must-not-commit'))
                        except pymysql.err.OperationalError as e:
                            if e.args[0] != 1290:
                                raise
                            record['readonly_rejected'] = True
                        else:
                            raise AssertionError('readonly endpoint accepted INSERT')
                    else:
                        c.begin()
                        key = 'ports-' + uuid.uuid4().hex
                        cur.execute('INSERT INTO ha_lab.events VALUES (%s,%s)', (key, 'verified'))
                        cur.execute('SELECT payload FROM ha_lab.events WHERE id=%s', (key,))
                        assert cur.fetchone() == ('verified',)
                        c.commit()
                        record['read_after_write'] = True
                record['result'] = 'PASS'
            except Exception as e:
                failures += 1
                record.update(result='FAIL', error_type=type(e).__name__, error_code=e.args[0] if e.args else None)
            finally:
                if c:
                    c.close()
            results.append(record)
    dump({'failures': failures, 'results': results})
    raise SystemExit(bool(failures))
else:
    end = time.monotonic() + args.seconds
    run = uuid.uuid4().hex
    c = None
    n = 0
    out = root / (args.label + '.jsonl')
    if out.exists() or (root / (args.label + '.stop')).exists():
        raise FileExistsError(out.name)
    with out.open('x', buffering=1) as file:
        while time.monotonic() < end and (not (root / (args.label + '.stop')).exists()):
            n += 1
            key = run + '-' + str(n)
            row = {'id': key, 'payload': 'synthetic-' + str(n), 'utc': datetime.datetime.now(datetime.timezone.utc).isoformat()}
            started = time.monotonic()
            try:
                if c is None:
                    c = connect()
                with c.cursor() as cur:
                    cur.execute('INSERT INTO ha_lab.events VALUES (%s,%s)', (key, row['payload']))
                row['ack'] = True
                row['ack_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
            except Exception as e:
                row.update(ack=False, error_type=type(e).__name__, error_code=e.args[0] if e.args else None)
                if c:
                    c.close()
                c = None
            row['latency_ms'] = round((time.monotonic() - started) * 1000, 3)
            file.write(json.dumps(row) + '\n')
            time.sleep(0.2)
    if c:
        c.close()
    dump({'attempts': n, 'ledger': out.name})
