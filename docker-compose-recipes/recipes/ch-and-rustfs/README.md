# ClickHouse with S3-compatible RustFS

**Beta / evaluation only:** this recipe pins RustFS **1.0.0-beta.12**, a prerelease. The walkthrough validates ClickHouse interoperability with that beta, not RustFS general production readiness. Do not float across beta releases.

This local example stores ClickHouse MergeTree data in RustFS through the generic S3 API. Both this recipe and [the SeaweedFS recipe](../ch-and-seaweedfs/README.md) insert the same checked-in, three-row fixture. This teaches S3 disk configuration, not a production storage deployment or backup/restore.

The stack contains one ClickHouse server, one RustFS container, and a short-lived AWS CLI setup container. The setup container creates the `clickhouse` bucket and verifies it before ClickHouse starts. ClickHouse stores table data under the bucket's `data/` prefix and keeps its metadata in the `clickhouse-data` volume. Both volumes are needed to preserve this example.

These are public development credentials: ClickHouse `demo` / `local-example-password`, S3 `local-access-key` / `local-secret-key`. Host ports bind only to loopback, but services use plain HTTP and containers on the recipe network can connect. Do not expose this stack or reuse its credentials in production.

## Prerequisites and versions

Use Docker Engine/Desktop or OrbStack with Docker Compose v2 and a POSIX shell. No host ClickHouse client, AWS CLI, Python packages, or npm dependencies are required. Allow roughly 4 GiB of Docker memory, 2 CPUs, and several GiB of disk for images and volumes. Linux amd64 and arm64 images are published; use a Linux Docker VM on macOS/Windows. Run these two recipes one at a time because both publish ClickHouse HTTP on `127.0.0.1:18123` and S3 on `127.0.0.1:18333`.

ClickHouse defaults to `CHVER=latest`; export `CHVER` before starting to override it. RustFS is pinned to `1.0.0-beta.12` and the setup image to AWS CLI `2.31.0`. The verification prints the actual ClickHouse version; a floating tag is not a compatibility guarantee.

Last manually verified: **2026-09-06**, ClickHouse **26.8.2.7**, RustFS **1.0.0-beta.12**, AWS CLI **2.31.0**, Linux **aarch64** on OrbStack (Docker 29.4.0 / Compose 5.1.2). The happy path passed from empty volumes: three rows, total 60, the Paris content assertion, active S3-backed parts, and 12 stored objects. This is a single-platform interoperability check.

## Start and verify

From this recipe directory, run the following block. The bucket setup makes at most 30 attempts, with each AWS request limited to 2 seconds to connect and 5 seconds to read; setup failure blocks ClickHouse startup. ClickHouse readiness also has 30 attempts. Inspect `docker compose logs --tail=100` if either fails.

```sh
set -eu
docker compose up -d
ready=false
attempt=0
while [ "$attempt" -lt 30 ]; do
  attempt=$((attempt + 1))
  if docker compose exec -T clickhouse clickhouse-client \
    --user demo --password local-example-password \
    --connect_timeout 3 --receive_timeout 10 --query 'SELECT 1' >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 2
done
[ "$ready" = true ]
q() {
  docker compose exec -T clickhouse clickhouse-client \
    --user demo --password local-example-password \
    --connect_timeout 3 --receive_timeout 65 --max_execution_time 60 --query "$1"
}
q 'SELECT version()'
q "CREATE TABLE events (id UInt32, city String, amount UInt32) ENGINE = MergeTree ORDER BY id SETTINGS storage_policy = 's3_store'"
q 'INSERT INTO events FORMAT TabSeparated' < fixture.tsv
[ "$(q 'SELECT count() FROM events')" = 3 ]
[ "$(q 'SELECT sum(amount) FROM events')" = 60 ]
[ "$(q 'SELECT city FROM events WHERE id = 2')" = Paris ]
[ "$(q "SELECT count() FROM system.parts WHERE database = 'default' AND table = 'events' AND active AND disk_name = 's3_store'")" -ge 1 ]
q 'SELECT * FROM events ORDER BY id'
# Verify that actual objects were written under the configured S3 disk prefix.
objects=$(docker compose run --rm --no-deps --entrypoint aws bucket-init \
  --endpoint-url http://rustfs:9000 --cli-connect-timeout 2 --cli-read-timeout 5 \
  s3api list-objects-v2 --bucket clickhouse --prefix data/ --query 'length(Contents)' --output json)
[ "$objects" -gt 0 ]
echo "OK: 3 rows, total 60, Paris content assertion, $objects S3 objects"
```

Expected rows:

```text
1  London  10
2  Paris   20
3  Berlin  30
```

The object count may change with ClickHouse versions and merges; it must be positive. The table-part check confirms that the active parts use `s3_store`, not the default local disk. Object storage holds ClickHouse's internal data files here; these are not standalone TSV or Parquet exports.

## Stop, rerun, and reset

`docker compose stop` preserves both volumes. To resume, use `docker compose up -d`. To repeat the creation/insertion walkthrough from empty state:

```sh
docker compose down -v --remove-orphans
```

This is destructive: it removes all ClickHouse tables and metadata and all RustFS objects in the recipe's named volumes. The checked-in fixture/configuration remain. Repeat the start/verify block after resetting. Do not delete only the ClickHouse metadata volume and expect this recipe to reconstruct tables from the bucket.

## ClickHouse Cloud and documentation

[ClickHouse Cloud](https://clickhouse.com/cloud) manages its own object storage, replication, and compute. Use Cloud for a managed analytics service; configuring its internal disks to point at this local store is not the equivalent path. For ingesting files from production object storage into Cloud, see [S3 ClickPipes](https://clickhouse.com/docs/integrations/clickpipes/object-storage); that ingests data into Cloud rather than replacing its storage layer.

- [ClickHouse S3 disk configuration](https://clickhouse.com/docs/operations/storing-data)
- [Official AWS CLI container](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-docker.html)
- [RustFS Docker documentation](https://docs.rustfs.com/en/installation/container/docker)
- [RustFS beta.12 release](https://github.com/rustfs/rustfs/releases/tag/1.0.0-beta.12)
