# ClickHouse and Vector: syslog and Apache JSON

One Vector agent parses a fixed RFC 5424 syslog line and an Apache-style JSON
line, then sends them to typed ClickHouse tables through its HTTP sink. Each
`demo_logs` source emits its fixture three times and finishes. The fixtures are
checked into [vector.toml](./fs/volumes/vector/vector.toml); no external dataset is
downloaded. This teaches parsing and ingestion, not production log collection or
exactly-once delivery.

Use Docker with Compose v2, a POSIX shell, roughly 4 GiB of Docker memory, 2 CPUs
and several GiB of disk. The images publish Linux amd64 and arm64 builds. All
clients run in containers; no host Vector, Python or npm dependencies are needed.
Vector is pinned to `0.58.0-alpine`. ClickHouse keeps `CHVER=latest`; export `CHVER`
before starting to select a different release.

Manually verified on **2026-09-06**, Linux arm64 on OrbStack (Docker 29.4.0 /
Compose 5.1.2), with ClickHouse **26.8.2.7** and Vector **0.58.0**. The complete
walkthrough passed from empty volumes: all fields matched in six rows, Apache
bytes totalled 384, and Vector exited successfully after draining the fixtures.

The public development credentials are `demo` / `local-example-password`.
ClickHouse HTTP is bound only to `127.0.0.1:18123`; Vector reaches it over the
private Compose network. Connections use plaintext. Do not expose this example
or reuse its credentials in production.

## Start and verify

From this recipe directory, run the complete block from empty volumes. ClickHouse
health checks wait for both tables before Vector starts. The poll below makes at
most 30 attempts, each with a 10-second query timeout. On failure, inspect
`docker compose logs --tail=100`.

```sh
set -eu
docker compose up -d
q() {
  docker compose exec -T clickhouse clickhouse-client \
    --user demo --password local-example-password \
    --connect_timeout 3 --receive_timeout 10 --max_execution_time 10 --query "$1"
}
q 'SELECT version()'
ready=false
attempt=0
while [ "$attempt" -lt 30 ]; do
  counts=$(q 'SELECT concat(toString((SELECT count() FROM syslog_raw_data)), char(58), toString((SELECT count() FROM apache_raw_data)))')
  if [ "$counts" = '3:3' ]; then ready=true; break; fi
  attempt=$((attempt + 1))
  sleep 2
done
[ "$ready" = true ]
[ "$(q "SELECT countIf(appname='demo-app' AND facility='user' AND hostname='demo-host' AND message='hello-vector' AND msgid='demo-id' AND procid=123 AND severity='info' AND source_type='demo_logs' AND timestamp='2026-09-06T12:00:00Z' AND version=1) FROM syslog_raw_data")" = 3 ]
[ "$(q "SELECT countIf(datetime='06/Sep/2026:12:00:00 +0000' AND host='127.0.0.1' AND method='GET' AND protocol='HTTP/1.1' AND referer='-' AND request='/example' AND status='200' AND bytes=128 AND \`user-identifier\`='demo') FROM apache_raw_data")" = 3 ]
q 'SELECT message, procid, count() FROM syslog_raw_data GROUP BY message, procid'
q 'SELECT request, status, sum(bytes) FROM apache_raw_data GROUP BY request, status'
echo 'OK: all fields match; 3 syslog rows and 3 Apache rows (384 bytes)'
```

Expected summary rows are `hello-vector / 123 / 3` and `/example / 200 / 384`,
followed by `OK`. Both ClickHouse schemas reject unknown fields, so the
verification checks the emitted event shape as well as delivery. The syslog
transform explicitly selects columns and converts process/version numbers; the
JSON transform preserves the fixture fields and normalizes numeric bytes/status.

Vector exits after the finite sources are drained. Its default retry behavior is
retained for transient sink errors; it no longer disables retries. The bounded
verification detects a failed demonstration, but it does not turn retries into
exactly-once delivery. Restarting Vector generates the fixtures again and appends
another three rows per table; failures/retries can also cause duplicates.

## Stop and reset

To repeat the exact assertions, remove the previous data first:

```sh
docker compose down -v --remove-orphans
```

This deletes the ClickHouse data volume. Checked-in fixtures/configuration remain.
`docker compose stop` preserves data, but restarting the finite generator replays
its fixtures, so a full reset is needed for the exact six-row walkthrough.

## ClickHouse Cloud

The same Vector ClickHouse sink can write to ClickHouse Cloud: create these two
tables in the service, replace the sink endpoint with its HTTPS endpoint on port
8443, and use the service's credentials and network allowlist. Keep TLS certificate
verification enabled. Cloud manages the destination; you still operate Vector
and choose its sources, buffering and delivery behavior. The Cloud path is not
part of this local manual run.

- [ClickHouse and Vector](https://clickhouse.com/docs/integrations/vector)
- [Vector ClickHouse sink](https://vector.dev/docs/reference/configuration/sinks/clickhouse/)
- [Finite demo-log sources](https://vector.dev/docs/reference/configuration/sources/demo_logs/)
- [Vector 0.58.0 release](https://vector.dev/releases/0.58.0/)
