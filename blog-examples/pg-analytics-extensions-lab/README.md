# Postgres analytics extensions lab: pg_duckdb vs pg_lake vs pg_clickhouse

A reproducible, single-host Docker lab that runs the same synthetic analytics workload four ways from one Postgres
instance and measures (a) query latency and (b) how much each approach hurts a concurrent OLTP workload.

- **plain** — stock Postgres 17 executor on the heap table (parallel seq scans, 4 workers per gather)
- **pg_duckdb** — DuckDB embedded in the Postgres backend, reading the heap table (`duckdb.force_execution = true`); optional variants with tuned settings and with a Parquet export
- **pg_lake** — Iceberg tables (Parquet on S3-compatible storage) queried through `pgduck_server`, a separate DuckDB process on the same host
- **pg_clickhouse** — foreign tables (`IMPORT FOREIGN SCHEMA`) over a ClickHouse MergeTree copy running in a separate container ("separate machine")

Results and interpretation: [RESULTS.md](RESULTS.md). Data: `results/queries/timings.csv`, `results/contention.csv`,
`results/explain/`, `results/correctness.txt`. Rerunning writes raw logs and per-query output under `results/`
too; those are gitignored.

> **Hardware.** The published results come from one AWS **m9gd.4xlarge** (Graviton5, 16 vCPU, 64 GiB, Amazon
> Linux 2023, Docker 25, Docker data on the local NVMe instance store), with containers capped by cgroups. It is
> laptop-sized on purpose. It is a lab, not a formal benchmark: one run per configuration and a small number of
> repetitions. Treat the numbers as directional and re-run them yourself. Any Linux host with 16+ cores works.

## Versions (as tested 2026-10-30)

| Component | Image / source | Version |
|---|---|---|
| pg_duckdb | `pgduckdb/pgduckdb:17-v1.1.1` (`sha256:302d06d0…`) | pg_duckdb 1.1.1 (SQL ext 1.1.0), DuckDB v1.4.3, PostgreSQL 17.7 |
| pg_clickhouse | `ghcr.io/clickhouse/pg_clickhouse:17` (`sha256:620d833a…`, built 2026-09-28) | pg_clickhouse 0.11 (latest published image; repo `main` is 0.12.0), PostgreSQL 17.11 |
| ClickHouse | `clickhouse/clickhouse-server:26.10.3.7` (`sha256:739e099a…`) | 26.10.3.7 |
| pg_lake | built from `Snowflake-Labs/pg_lake` @ `1918df64e9655671036037051c8507949a953595` (pinned in the Dockerfile) with the repo's `docker/Dockerfile` (see deviations) | PostgreSQL 17.11 compiled from source, pgduck_server + duckdb_pglake from the same commit |
| S3 for pg_lake | `chrislusf/seaweedfs:latest` (`sha256:c2658820…`) | 4.50 (ec8f97935) |
| client / pgbench | `postgres:17` | pgbench 17 |

Repos are cloned (shallow) into `vendor/` for reference and for the pg_lake build context. `vendor/` is a
scratch area: do not commit it (treat it as gitignored). Commit SHAs at clone time:
pg_lake `1918df6`, pg_clickhouse `35cdcac`, pg_duckdb `a9457c9`.

## Topology and resource caps

| Container | Role | CPU | Memory |
|---|---|---|---|
| `lab-pgch` / `lab-pgduck` / `lab-pglake` | Postgres instance under test (one runs at a time during measurements) | `--cpus=4`, pinned to cores 0-3 | 4 GiB, no swap, `--shm-size=1g` |
| `lab-pgduck-server` | pg_lake's DuckDB process | pinned to the **same** cores 0-3 as `lab-pglake` | 4 GiB (separate cgroup, see deviations) |
| `lab-ch` | ClickHouse ("separate machine") | `--cpus=4`, cores 8-11 | 4 GiB |
| `lab-client` | psql + pgbench load generator | cores 4-7 | uncapped |
| `lab-s3` | SeaweedFS S3 for pg_lake | cores 12-13 | 3 GiB |

Identical Postgres tuning on every instance: `shared_buffers=1GB`, `work_mem=64MB`,
`max_parallel_workers_per_gather=4`, plus `max_wal_size=4GB`, `maintenance_work_mem=512MB`,
`max_connections=100` (to keep the load fast). Everything else is the image default.

## Dataset

`sql/01_gen_events.sql` — deterministic (`generate_series` + `hashint8extended`), so every instance gets
byte-identical rows:

- `events`: 50,000,000 rows, ~180 days from 2026-01-01 UTC, `user_id` ~5M distinct, 14 distinct `event_type`
  values drawn from a 20-slot weighted list, 40 countries, URLs with 800k distinct values, `revenue` non-zero on
  ~10% of rows. Heap size 7.6 GB with PK + `event_time` B-tree index.
- `users`: 5,000,000 rows (dimension for the join query).

Load per path:
- plain / pg_duckdb: the heap tables directly. pg_duckdb Parquet variant: `COPY … TO '…parquet'` via DuckDB (`sql/duckdb_parquet_setup.sql`).
- pg_lake: `CREATE TABLE ice.events USING iceberg AS SELECT * FROM public.events` (`sql/pglake_setup.sql`).
- pg_clickhouse: `INSERT INTO lab.events SELECT * FROM postgresql('lab-pgch:5432', …)` into MergeTree
  `ORDER BY event_time` (`sql/ch_schema.sql`, `scripts/02_load_clickhouse.sh`), then `IMPORT FOREIGN SCHEMA lab
  FROM SERVER ch_srv INTO ch` (`sql/pgch_setup.sql`). In production this copy would be continuous CDC
  (e.g. ClickPipes for Postgres); the one-shot copy is only for the lab.

## Queries

`sql/queries/Q1..Q6.sql` — identical SQL text for every path; the path is selected with `search_path`
(`public` heap, `ice` Iceberg, `ch` foreign tables, `duckpq` Parquet views) and, for pg_duckdb, `SET duckdb.force_execution = true`.

| Q | What |
|---|---|
| Q1 | `count(*)`, `sum(revenue)` full scan |
| Q2 | `GROUP BY event_type` |
| Q3 | `GROUP BY country, date_trunc('day', event_time)` for one month and 3 event types |
| Q4 | `GROUP BY user_id ORDER BY sum(revenue) DESC LIMIT 10` (5M groups) |
| Q5 | `count(DISTINCT user_id)` |
| Q6 | join one month of events to the 5M-row `users` table, `GROUP BY plan` |

## How to reproduce

```bash
git clone https://github.com/ClickHouse/examples.git
cd examples/blog-examples/pg-analytics-extensions-lab
git clone https://github.com/Snowflake-Labs/pg_lake.git vendor/pg_lake && git -C vendor/pg_lake checkout 1918df64
BUILD_NCORES=16 scripts/00_build_pg_lake.sh   # builds pg_lake:lab-pg17 + pgduck-server:lab-pg17 (~13 min on 16 cores)

# Either run everything in one go (loads overlap the build, every measurement waits for it):
scripts/run_all.sh

# ...or step by step:
scripts/01_up.sh all                   # client, ClickHouse, pg_duckdb, pg_clickhouse containers
scripts/01_up.sh pglake                # pg_lake + pgduck_server + SeaweedFS (pgduck_server needs ~20-60 s before it accepts queries)
for c in lab-pgch lab-pgduck lab-pglake; do scripts/02_gen_events.sh $c; scripts/02_init_pgbench.sh $c; done
scripts/02_load_clickhouse.sh          # MergeTree copy + IMPORT FOREIGN SCHEMA
docker exec -i lab-client psql -h lab-pglake -U postgres -f /lab/sql/pglake_setup.sql
docker exec -i lab-client psql -h lab-pgduck -U postgres -f /lab/sql/duckdb_parquet_setup.sql   # optional

# query latency: 10 cold runs (containers restarted + OS page cache dropped before each; pg_lake's file cache
# emptied too) + 1 warm-up and 10 warm runs, per query. COLD_RUNS / WARM_RUNS override the counts.
for p in plain ch duckdb duckdb_tuned duckdb_parquet lake; do scripts/03_bench_queries.sh $p; done
for p in plain ch duckdb lake; do scripts/04_explain.sh $p; done
scripts/compare_results.py             # checks every path returns the same answers

# contention: pgbench -c16 -j4 (scale 50) alone, then with a Q3+Q4 loop through each path
scripts/06_contention_all.sh           # TPC-B, 120 s, baselines before and after  -> results/contention/
scripts/07_contention_select_only.sh   # pgbench -S, 60 s (CPU-bound variant)     -> results/contention_select_only/
scripts/make_tables.py [latency|contention|contention_select_only]   # markdown tables used in RESULTS.md
scripts/export_results.py              # writes results/contention.csv + results/correctness.txt
scripts/99_teardown.sh                 # removes containers + volumes, keeps scripts/results
```

Only one Postgres instance should be under load while you measure (they all share cores 0-3).



## Deviations from "stock" (all deliberate, all disclosed)

1. **pg_lake has no official prebuilt image**, so it is built from the repo's own `docker/Dockerfile`. Copy in
   `docker/pg_lake.Dockerfile` with two changes: the `dev_base` stage only compiles PostgreSQL 17 (+ its PostGIS,
   pgaudit, pg_cron, pg_incremental) instead of 16/17/18/19, the DuckDB compile parallelism is a build arg
   (`BUILD_NCORES`, default 8; upstream recommends 16 GB+ RAM for the build), and the pg_lake source is pinned to
   the commit above instead of a branch. PG 17 was chosen over 18 because the upstream Dockerfile compiles PG 18
   with `--enable-cassert` (assertion-enabled build), which would unfairly slow pg_lake; PG 17 is built without
   asserts. It is still built with `--enable-debug` (symbols only, `-O2`).
2. **Object storage**: upstream compose uses localstack; `localstack/localstack:latest` now requires an auth
   token and the MinIO images are no longer on Docker Hub, so SeaweedFS's S3 gateway stands in, under the
   network alias `localstack:4566` so upstream's `init-pgduck-server.sql` secret works unchanged.
3. **pg_lake entrypoint**: `docker/entrypoint-pglake.sh` is upstream's `entrypoint-postgres.sh` plus the lab
   `postgresql.conf` tuning block.
4. **pg_lake memory**: `pgduck_server` is a separate process in a separate container. It shares the same 4
   pinned cores as Postgres (so CPU contention is realistic), but it has its own 4 GiB memory cgroup, so the
   pg_lake path effectively gets 8 GiB of RAM vs 4 GiB for the others. This favours pg_lake on memory.
5. **pg_duckdb**: default settings for the main run (DuckDB detects 4 threads from the cgroup; `duckdb.max_memory`
   defaults to 4096 MB). A `duckdb_tuned` variant sets `duckdb.max_memory=2048`,
   `duckdb.max_workers_per_postgres_scan=4`, `duckdb.threads_for_postgres_scan=4`.
6. **ClickHouse schema**: `LowCardinality(String)` for `event_type`/`country`, `DateTime64(6,'UTC')`,
   `Decimal(10,2)`, `ORDER BY event_time` — a normal ClickHouse modelling choice, not a heap-equivalent layout.
7. **Cold runs** = `docker restart` of the path's containers + `echo 3 > /proc/sys/vm/drop_caches` on the host.
   For pg_duckdb this includes DuckDB instance start-up in the new backend. For pg_lake, pgduck_server's on-disk
   file cache (`--cache_dir`, which persists across restarts by design) is emptied as well, so cold queries read
   from object storage; SeaweedFS keeps running, as S3 would. Warm pg_lake runs wait until the cache manager has
   downloaded the files the warm-up query read.
8. In `run_all.sh` the data loads for pg_duckdb, pg_clickhouse and ClickHouse overlap the pg_lake build; nothing
   is measured until the build has finished.

## Layout

```
docker/          pg_lake Dockerfile copy, entrypoint, lab postgresql.conf
scripts/         00_build … 07_contention, run_all.sh, 99_teardown, env.sh, paths.sh,
                 summarise_contention.py, compare_results.py, make_tables.py, export_results.py
sql/             data generator, per-path setup, queries/Q1..Q6.sql
results/         queries/timings.csv, contention.csv, explain/<path>.txt, correctness.txt, host_info.txt
                 (raw logs and per-run output are written here too, but gitignored)
vendor/          clone of pg_lake for the build context (gitignored)
```
