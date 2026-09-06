# ClickHouse with one Keeper

A single ClickHouse server and one Keeper demonstrate coordinated table metadata with a tiny replicated table. This does not teach production availability, TLS, or backups.

These are local teaching configurations, not production deployments. Published ports bind to `127.0.0.1`, but the default ClickHouse user has no password and containers on the recipe network can connect. Do not expose these ports or reuse the example credentials on a shared host.

## Prerequisites

Use Docker Engine/Desktop or OrbStack with Docker Compose v2, Bash, and curl. Allocate roughly 4 GiB of Docker memory and 2 CPUs, with several GiB of free disk for images and logs. ClickHouse and Keeper images support Linux amd64 and arm64; use a Docker Linux VM on macOS/Windows. Run one recipe at a time: the fixed container names and host ports overlap across examples.

ClickHouse defaults to `CHVER=latest` and Keeper to `CHKVER=latest-alpine`. To select other images, export `CHVER` and `CHKVER` before starting; these overrides are intentionally retained. The verification prints the actual server version. Floating tags are not a compatibility guarantee.

Last manually verified: **2026-09-06**, ClickHouse **26.8.2.7**, Keeper **26.8.2.7**, Linux **aarch64** on OrbStack (Docker 29.4.0 / Compose 5.1.2). The complete happy path below passed from empty volumes; this is a single-platform manual check.

## Start and verify

From this recipe directory, run the following Bash block. It polls each server's Keeper connection at most 30 times (each request is limited to 10 seconds); subsequent SQL requests are limited to 60 seconds. If it fails, inspect `docker compose logs --tail=100`.

```bash
set -eu
docker compose up -d
for port in 8123; do
  ready=false
  for attempt in {1..30}; do
    if curl --fail --silent --max-time 10 "http://127.0.0.1:$port/" \
      --data-binary "SELECT count() FROM system.zookeeper WHERE path = '/'" >/dev/null; then
      ready=true
      break
    fi
    sleep 2
  done
  if [ "$ready" != true ]; then
    echo "ClickHouse/Keeper not ready on port $port" >&2
    exit 1
  fi
done
q() {
  curl --fail --silent --show-error --max-time 60 \
    'http://127.0.0.1:8123/?distributed_ddl_task_timeout=60' --data-binary "$1"
}
q 'SELECT version()'
q "CREATE TABLE demo (id UInt32, message String) ENGINE = ReplicatedMergeTree('/clickhouse/tables/demo', 'replica-1') ORDER BY id"
q "INSERT INTO demo VALUES (1, 'hello keeper')"
[ "$(q 'SELECT count() FROM demo')" = 1 ]
[ "$(q 'SELECT message FROM demo WHERE id = 1')" = 'hello keeper' ]
q 'SELECT * FROM demo'
echo 'OK: one row in a Keeper-coordinated table'
```

Expected output includes the actual ClickHouse version, `1 / hello keeper`, and the final `OK` line. Keeper coordinates the table metadata; one server and one Keeper do not provide redundancy.

## Stop, rerun, and reset

`docker compose stop` preserves the existing containers for `docker compose start`. Before repeating the creation/insertion walkthrough, reset to empty state:

```bash
docker compose down -v --remove-orphans
```

This is destructive: it removes recipe containers and their anonymous data volumes, including all inserted data and Keeper state. The checked-in configuration and fixture remain. Then repeat the start/verify block. These examples are disposable and do not configure durable host data directories.

## ClickHouse Cloud and documentation

[ClickHouse Cloud](https://clickhouse.com/cloud) manages the service's replication and scaling. Keeper wiring, explicit shard layouts, and CHProxy are self-managed infrastructure lessons; do not copy this Compose topology into Cloud.

- [ClickHouse architecture](https://clickhouse.com/docs/architecture/introduction)
- [ReplicatedMergeTree](https://clickhouse.com/docs/engines/table-engines/mergetree-family/replication)
- [Distributed tables](https://clickhouse.com/docs/engines/table-engines/special/distributed)
- [ClickHouse Keeper](https://clickhouse.com/docs/guides/sre/keeper)
