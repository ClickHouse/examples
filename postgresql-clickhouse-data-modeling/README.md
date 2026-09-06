# Postgres to ClickHouse CDC with PeerDB

PostgreSQL handles transactional writes; PeerDB copies an initial snapshot and streams changes to ClickHouse for analytics. This is the canonical open-source CDC walkthrough in this repository. The default uses six tiny synthetic rows across four Stack Overflow-shaped tables, so startup does not download a multi-gigabyte dataset.

For the managed equivalent, follow [Postgres managed by ClickHouse → ClickHouse Cloud through a Postgres CDC ClickPipe](./MANAGED.md). Creating the two services alone does not configure replication: the ClickPipe is an explicit step. For optional query offload, see the separate [unified Postgres/ClickHouse stack](https://github.com/ClickHouse/postgres-clickhouse-stack); `pg_clickhouse` is not required for this CDC lesson.

This Compose stack is for local development, not production deployment. Published ports bind to loopback, traffic is not encrypted, and every credential below is a public example value. Do not expose it on a shared host or reuse these passwords.

## Components and requirements

The local stack contains the source Postgres, ClickHouse, PeerDB's API/workers/SQL server, a separate Postgres catalog, Temporal, and MinIO. The Temporal and MinIO setup containers exit after successful setup. MinIO is **PeerDB OSS's bundled internal transient S3 stage**: both PeerDB and ClickHouse connect to `minio:9000`. This preserves the upstream staging design; it is not the removed standalone MinIO recipe. PeerDB UI and Temporal UI are optional.

Use Docker Engine/Desktop or OrbStack with Docker Compose v2 and a POSIX shell. Allocate roughly 8 GiB of Docker memory, 4 CPUs, and at least 10 GiB of disk for images and volumes. The published images support Linux amd64 and arm64; the exact manual platform is recorded below. Docker supplies the Postgres/ClickHouse clients and the Python standard-library bootstrap helper; no host pip, npm, AWS CLI, or database clients are required.

| Endpoint | Address from the host | Development credentials |
| --- | --- | --- |
| Source Postgres | `127.0.0.1:15432`, database `clickhouse_pg_db` | `admin` / `password` |
| ClickHouse HTTP | `127.0.0.1:18123`, database `stackoverflow` after init | `demo` / `local-example-password` |
| PeerDB UI, optional | `http://localhost:13000` | Local development configuration |
| Temporal UI, optional | `http://localhost:18085` | Local development configuration |

The catalog, flow API, workers, PeerDB SQL server, and MinIO are internal to the Compose network. No `host.docker.internal` routing is needed. The catalog password is `postgres`, PeerDB SQL password is `local-peerdb-password`, and bundled MinIO credentials are `_peerdb_minioadmin` / `_peerdb_minioadmin`.

ClickHouse intentionally defaults to `${CHVER:-latest}`; export `CHVER` before starting to select another image. PeerDB components use `stable-v0.37.5`; supporting image tags/digests follow its official OSS stack. A floating ClickHouse tag is not a compatibility guarantee.

Last manually verified: **2026-09-06**, Linux **aarch64** on OrbStack (Docker 29.4.0 / Compose 5.1.2). Initial snapshot and the insert/update/delete assertions passed from empty volumes with ClickHouse **26.8.2.7**, PeerDB **stable-v0.37.5**, source Postgres **17.11**, catalog Postgres **18.6**, Temporal **1.29.7**, MinIO **RELEASE.2025-09-07T16-13-09Z** (bundled mc **RELEASE.2025-08-13T08-35-41Z**), and Python **3.12.14**. The Temporal setup uses upstream's admin-tools **1.25.2-tctl-1.18.1-cli-1.1.1** image. Optional UIs and the managed path were not runtime-validated.

## Start, snapshot, and verify changes

From this directory, run the following block from empty volumes:

```sh
set -eu
./run.sh
./init.sh
./verify.sh initial
./generate-activity.sh
./verify.sh changed
```

`run.sh` starts the stack. Temporal and MinIO setup must complete successfully before the API/workers start. `init.sh` waits for the databases, inserts [the tiny fixture](./fixtures/seed.sql), creates the two peers through PeerDB's API, and creates the four-table CDC mirror. API responses are checked for application errors as well as HTTP errors, so an HTTP 200 response containing `FAILED` does not report success.

Each database/API startup poll makes at most 30 attempts. MinIO CLI calls have a 15-second timeout, Temporal requests have a 5-second timeout, and API requests have a 15-second timeout. Each `verify.sh` run polls for up to 180 seconds, with an in-flight query limited to 10 seconds. Failures return a nonzero exit code. Inspect `docker compose logs --tail=100` for details.

The first verification checks the initial snapshot: two users, two posts, one vote, and one comment, including the exact user IDs/names. The mutation script applies [one insert, update, and delete](./fixtures/changes.sql) in a source transaction. The second verification must show exactly:

```text
1  Updated User
3  New User
OK: changed logical state; 2 users, 2 posts, 1 vote, 1 comment
```

User 3 was inserted, user 1 changed, and user 2 disappeared from the logical current state. The other three tables retain their fixture counts. The fixture is invented example data, not actual Stack Overflow user records. Run the creation/mutation scripts once per reset; repeated explicit-ID inserts are expected to fail.

## Querying CDC data correctly

PeerDB creates ReplacingMergeTree tables. Inserts and updates can leave multiple physical versions of a row; `_peerdb_version` identifies newer versions. Deletes add a row marked by `_peerdb_is_deleted`, and `_peerdb_synced_at` records synchronization time. Background merges are asynchronous, so raw `count()` is not the logical source row count.

Use `FINAL` to resolve versions at query time, then filter deleted rows:

```sh
docker compose exec -T clickhouse clickhouse-client \
  --user demo --password local-example-password \
  --query 'SELECT id, displayname FROM stackoverflow.users FINAL WHERE _peerdb_is_deleted = 0 ORDER BY id'
```

`verify.sh` uses those same semantics and compares complete user state, not physical row counts. The local ClickHouse account is deliberately privileged for the small demonstration; see the upstream setup guide for scoped production grants.

## Stop and reset

`docker compose stop` preserves data; `./run.sh` resumes it. To start again with an empty source, catalog, mirror state, stage, and destination:

```sh
docker compose --profile ui --profile tools down -v --remove-orphans
```

**Destructive:** `down -v` deletes every recipe named volume, including downloaded files in the optional dataset cache. The checked-in schema and fixtures remain. Repeat the main start/verify block after resetting. Do not reset only one database and expect the old CDC mirror to resume correctly.

## Optional UI and larger dataset

To inspect the running mirror, enable the UI profile:

```sh
docker compose --profile ui up -d peerdb-ui temporal-ui
```

The UI is optional and not part of the CDC happy-path acceptance. The native clients also work without publishing more ports:

```sh
docker compose exec postgres psql -U admin -d clickhouse_pg_db
docker compose exec clickhouse clickhouse-client --user demo --password local-example-password
```

The larger public Stack Overflow dataset remains an explicit extension. It downloads multiple gigabytes, needs substantially more disk/memory/time, and is not included in the manual CDC run. The importer runs only inside a container. From a destructive reset, with **no tiny fixture inserted**, run:

```sh
set -eu
./run.sh
docker compose --profile tools run --rm --build loader
./init.sh --existing-data
```

The loader writes rows in batches and propagates download/COPY errors. A small container regression checks batch boundaries, quoted multiline values, null/empty strings, rollback, and generated IDs; the complete multi-gigabyte import has not been manually run in this refresh. `--existing-data` skips the tiny fixture but still creates the peers/mirror. Do not run the tiny-fixture assertions or `generate-activity.sh` against this larger dataset; their IDs and expected names belong to the synthetic example.

## Primary documentation

- [Postgres and ClickHouse open-source architecture](https://clickhouse.com/blog/postgres-clickhouse-oss)
- [PeerDB OSS Compose stack](https://github.com/PeerDB-io/peerdb/blob/main/docker-compose.yml)
- [PeerDB ClickHouse setup and internal MinIO stage](https://docs.peerdb.io/connect/clickhouse/clickhouse)
- [PeerDB API: create a Postgres peer](https://docs.peerdb.io/peerdb-api/endpoints/create-peer/postgres)
- [PeerDB API: create a ClickHouse peer](https://docs.peerdb.io/peerdb-api/endpoints/create-peer/clickhouse)
- [PeerDB API: create a mirror](https://docs.peerdb.io/peerdb-api/endpoints/create-mirror)
- [PeerDB version/deletion columns and data modeling](https://docs.peerdb.io/bestpractices/clickhouse_datamodeling)
