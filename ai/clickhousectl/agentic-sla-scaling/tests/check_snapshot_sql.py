"""Check SLA aggregation on a local server using a session-only fixture table.

Usage: python3 tests/check_snapshot_sql.py --port 19000
No Cloud credentials or persistent schema changes are used.
"""
import argparse
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--port', type=int, required=True, help='Native port of a local test server')
args = parser.parse_args()
source = (Path(__file__).resolve().parents[1] / 'sla.sql').read_text()
# Use the production query unchanged except for its source table. This isolates
# time-window, event-type and initial-request semantics from asynchronous logs.
query = source.replace('clusterAllReplicas(default, system.query_log)', 'sla_snapshot_fixture')
sql = f"""
CREATE TEMPORARY TABLE sla_snapshot_fixture
(
    event_time DateTime,
    type String,
    query_duration_ms UInt64,
    is_initial_query UInt8,
    log_comment String
) ENGINE = Memory;

SELECT throwIf(completed != 0 OR failed != 0 OR p99_ms != 0, 'empty window mismatch')
FROM ({query});

INSERT INTO sla_snapshot_fixture
SELECT now(), 'QueryFinish', 50, 1, 'frontend-dashboard' FROM numbers(99);
INSERT INTO sla_snapshot_fixture VALUES
(now(), 'QueryFinish', 400, 1, 'frontend-dashboard'),
(now(), 'ExceptionBeforeStart', 5000, 1, 'frontend-dashboard'),
(now(), 'ExceptionWhileProcessing', 6000, 1, 'frontend-dashboard'),
(now(), 'QueryStart', 7000, 1, 'frontend-dashboard'),
(now(), 'QueryFinish', 8000, 0, 'frontend-dashboard'),
(now() - INTERVAL 2 MINUTE, 'QueryFinish', 9000, 1, 'frontend-dashboard'),
(now(), 'QueryFinish', 10000, 1, 'analytics-batch');

SELECT throwIf(completed != 100 OR failed != 2 OR p99_ms != 400, 'populated window mismatch')
FROM ({query});
"""
subprocess.run(['clickhouse', 'client', '--host', '127.0.0.1', '--port', str(args.port),
                '--multiquery', '--query', sql], check=True, timeout=30)
print('SLA SQL checks passed: empty window, exact tail, failures, initial requests, tags and age.')
