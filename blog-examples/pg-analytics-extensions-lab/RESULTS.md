# Results: pg_duckdb vs pg_lake vs pg_clickhouse (lab run 2026-10-30)

Setup, versions and deviations: [README.md](README.md). Raw outputs: `results/`.

One AWS **m9gd.4xlarge** (Graviton5, 16 vCPU, 64 GiB, Amazon Linux 2023, Docker data on the local NVMe
instance store). Every Postgres instance was capped at 4 CPUs (pinned to the same cores 0-3) and 4 GiB;
ClickHouse 26.10 ran in its own 4 CPU / 4 GiB container on cores 8-11; the pgbench/psql client on cores 4-7;
50M-row `events` table + 5M-row `users` table. **One host, one run per configuration, not a formal benchmark.**

Correctness: `scripts/compare_results.py` confirms every path returned identical results for all six queries.

## 1. Query latency (no concurrent OLTP load)

Wall-clock from `psql \timing` in the client container. Cold = path's containers restarted + OS page cache
dropped; warm = median of the next 3 runs in the same session.

#### Warm (median of runs 2-4)

| Query | plain PG | pg_duckdb (heap, defaults) | pg_duckdb (heap, tuned¹) | pg_duckdb (Parquet²) | pg_lake (Iceberg) | pg_clickhouse |
|---|---:|---:|---:|---:|---:|---:|
| Q1 count+sum | 2.35 s | 4.32 s | 3.89 s | 68 ms | 140 ms | 55 ms |
| Q2 group by event_type | 2.12 s | 4.89 s | 4.77 s | 92 ms | 226 ms | 103 ms |
| Q3 country × day, 1 month | 552 ms | 793 ms | 549 ms | 115 ms | 556 ms | 60 ms |
| Q4 top-10 users (5M groups) | 13.66 s | **OOM-killed** | 5.22 s | 1.02 s | 1.08 s | 563 ms |
| Q5 count(DISTINCT user_id) | 10.14 s | 3.38 s | 3.41 s | 392 ms | 598 ms | 440 ms |
| Q6 join 5M users, 1 month | 1.72 s | 1.69 s | 1.59 s | 286 ms | 1.04 s | 298 ms |

#### Cold (run 1)

| Query | plain PG | pg_duckdb (defaults) | pg_duckdb (tuned¹) | pg_duckdb (Parquet²) | pg_lake | pg_clickhouse |
|---|---:|---:|---:|---:|---:|---:|
| Q1 | 1.33 s | 4.44 s | 3.78 s | 118 ms | 165 ms | 74 ms |
| Q2 | 1.97 s | 5.53 s | 4.99 s | 162 ms | 277 ms | 130 ms |
| Q3 | 1.15 s | 1.56 s | 1.17 s | 164 ms | 627 ms | 92 ms |
| Q4 | 13.82 s | 5.71 s | 5.46 s | 1.21 s | 1.17 s | 627 ms |
| Q5 | 10.21 s | 4.12 s | 3.57 s | 541 ms | 691 ms | 408 ms |
| Q6 | 2.24 s | 2.33 s | 1.99 s | 450 ms | 1.09 s | 354 ms |

¹ `duckdb.max_memory=2048`, `duckdb.max_workers_per_postgres_scan=4`, `duckdb.threads_for_postgres_scan=4`.
² Heap exported once to local Parquet with DuckDB `COPY … TO` (19.8 s for 50M rows), queried via `read_parquet` views, `duckdb.max_memory=2048`.

Plain Postgres warm runs are not faster than cold here: the 7.6 GB heap does not fit in the 4 GiB container's
memory cgroup (page cache counts against it), so every scan rereads from the NVMe drive.

Pushdown (from `results/explain/`):
- **pg_clickhouse: all six queries fully pushed down** as a single `Foreign Scan` with remote SQL, including
  `count(DISTINCT)`, `date_trunc('day')` → `toStartOfDay`, `ORDER BY … LIMIT`, and the events⋈users join
  (`ALL INNER JOIN` executed in ClickHouse).
- **pg_lake: all six fully pushed down** (`Custom Scan (Query Pushdown)`, Engine: DuckDB).
- **pg_duckdb: all six run in DuckDB** (`Custom Scan (DuckDBScan)`), but the leaf is always
  `PGDUCKDB_POSTGRES_SCAN` — DuckDB reads heap tuples through Postgres (time filters are pushed into that scan).
- plain PG: parallel seq/index scans with 4 workers, except Q5 (`count(DISTINCT)` is not parallelised).

What the latency numbers say:
- **pg_duckdb on heap tables is not a universal accelerator.** Tuned, it was *slower* than plain Postgres on
  simple scans and low-cardinality aggregates (Q1 1.7×, Q2 2.3× slower), even on Q3 and Q6, and faster only
  where Postgres is weak: high-cardinality aggregation (Q4 2.6×) and `count(DISTINCT)` (Q5 3×). The bottleneck is
  reading row-format heap pages through the Postgres scan, not DuckDB's engine.
- **The same DuckDB on columnar data is fast.** pg_duckdb on a Parquet copy was ~5-57× faster than on the heap
  (5-9× on Q3-Q6, 52-57× on Q1-Q2). pg_lake (also DuckDB, over Iceberg/Parquet on S3-compatible storage) was
  slower than local Parquet because of the extra hop to pgduck_server and object-storage reads. The large
  speed-ups from both DuckDB extensions come from *changing the storage format* (a second copy of the data), not
  from running against the live OLTP tables.
- **pg_clickhouse and pg_duckdb-over-Parquet were close.** pg_clickhouse was faster on Q1, Q3 and Q4 (up to
  1.9×); pg_duckdb over Parquet was faster on Q2, Q5 and Q6 (by 4-11%). Against the paths that query live data
  in Postgres (plain PG, pg_duckdb on heap), pg_clickhouse was 5-71× faster (vs plain and tuned pg_duckdb).
- Every fast path needs a data copy: Parquet export (pg_duckdb, 19.8 s), Iceberg CTAS (pg_lake, 51 s for 50M
  rows), or MergeTree (pg_clickhouse, 28 s one-shot load via `postgresql()`; CDC in production).

## 2. Contention: OLTP throughput while analytics runs

`pgbench -c 16 -j 4` (scale 50, `pgbench` DB in the **same** Postgres instance as the events data) with and
without one psql session looping Q3 + Q4 through each path. Δ TPS is vs the mean of that instance's baseline
runs. CPU% from `docker stats` (100% = 1 core; the Postgres containers are capped at 400%). At baseline
Postgres used ~396% of its 400% on both tests, so both are CPU-bound on this host (the NVMe makes commits cheap).

### 2a. TPC-B (default pgbench, read-write, 120 s)

| Run | TPS | Δ TPS | p95 lat | p99 lat | analytics completed in 120 s (Q3 / Q4, median ms) | Postgres CPU avg | pgduck_server CPU avg | ClickHouse CPU avg |
|---|---:|---:|---:|---:|---|---:|---:|---:|
| baseline pgch r1 / r2 | 17,291 / 17,047 | — | 1.35 / 1.36 ms | 1.72 / 1.72 ms | — | 396% | — | 2% |
| + plain PG loop | 10,200 | **-41%** | 4.67 ms | 10.29 ms | 5 / 4 (2.6 s / 27.6 s) | 390% | — | 2% |
| + pg_clickhouse loop | 17,137 | **-0.2%** | 1.36 ms | 1.73 ms | 74 / 73 (59 ms / 1.56 s) | 380% | — | 158% |
| baseline pgduck r1 / r2 | 17,318 / 17,343 | — | 1.36 / 1.35 ms | 1.76 / 1.70 ms | — | 396% | — | 2% |
| + pg_duckdb loop (defaults) | 9,362 | **-46%, run aborted** | 2.79 ms | 4.10 ms | 2 / 1, then backend OOM-killed | 353% | — | 3% |
| + pg_duckdb loop (tuned) | 10,834 | **-37%** | 2.53 ms | 3.98 ms | 9 / 8 (3.5 s / 11.3 s) | 387% | — | 2% |
| baseline pglake r1 / r2 | 17,879 / 17,927 | — | 1.32 / 1.32 ms | 1.76 / 1.77 ms | — | 395% | 0% | 2% |
| + pg_lake loop | 7,805 | **-56%** | 6.98 ms | 11.10 ms | 51 / 50 (719 ms / 1.81 s) | 182% | 203% | 2% |

Baselines repeated within 1.5% on every instance. Raw logs: `results/contention/`.

### 2b. Select-only (pgbench -S, 60 s)

| Run | TPS | Δ TPS | p95 lat | p99 lat | analytics completed in 60 s (Q3 / Q4, median ms) | Postgres CPU avg | pgduck_server CPU avg | ClickHouse CPU avg |
|---|---:|---:|---:|---:|---|---:|---:|---:|
| baseline pgch | 118,680 | — | 0.24 ms | 0.28 ms | — | 402% | — | 3% |
| + plain PG loop | 94,494 | **-20%** | 0.45 ms | 0.62 ms | 2 / 1 (2.2 s / 36.8 s) | 391% | — | 3% |
| + pg_clickhouse loop | 116,575 | **-1.8%** | 0.20 ms | 0.26 ms | 40 / 39 (59 ms / 1.57 s) | 370% | — | 154% |
| baseline pgduck | 120,458 | — | 0.23 ms | 0.28 ms | — | 403% | — | 5% |
| + pg_duckdb loop (tuned) | 98,390 | **-18%** | 0.36 ms | 0.71 ms | 3 / 3 (3.3 s / 20.5 s) | 383% | — | 5% |
| baseline pglake | 120,225 | — | 0.19 ms | 0.25 ms | — | 403% | 0% | 5% |
| + pg_lake loop | 76,517 | **-36%** | 0.27 ms | 1.33 ms | 20 / 19 (822 ms / 2.53 s) | 242% | 142% | 5% |

### Memory behaviour

- **pg_duckdb defaults are unsafe in a 4 GiB instance.** `duckdb.max_memory` defaults to 4096 MB *per backend*,
  on top of `shared_buffers=1GB`. In the latency run Q4 completed once (5.7 s) and the backend was then killed by
  the container's memory cgroup (signal 9). In the TPC-B contention run with defaults the same happened after
  one Q4. Postgres treats a SIGKILLed backend as a crash: the postmaster terminates **every** connection and runs
  crash recovery, so the pgbench run aborted. With `duckdb.max_memory=2048` there were no OOMs, but the Postgres
  container still peaked at ~3.7 GiB of its 4 GiB cap.
- pg_lake's DuckDB lives in pgduck_server with its own memory limit (default 80% of system memory). In this lab
  it had a separate 4 GiB cgroup and peaked at 2.9 GiB, so analytics memory pressure never touched the Postgres
  cgroup (Postgres stayed under 1 GiB). On a single real host it would share RAM with Postgres.
- pg_clickhouse: the Postgres container peaked at ~1.4 GiB (TPC-B) to ~2.8 GiB (select-only) and ClickHouse used
  up to 2.2 GiB in its own container. No OOMs anywhere outside the pg_duckdb default runs.

## 3. Interpretation vs the hypothesis

> "In-process extensions accelerate queries but compete with OLTP for the same CPU/RAM; pg_clickhouse offloads compute to ClickHouse."

- **Competes with OLTP: confirmed.** Analytics through pg_duckdb and pg_lake cut OLTP throughput about as much as
  running them on plain Postgres: −37% (pg_duckdb tuned) and −56% (pg_lake) on TPC-B, −18% / −36% on
  select-only, vs −41% / −20% for plain Postgres. pg_lake running DuckDB in a separate process does not help when
  that process is on the same cores: pgduck_server took ~1.4-2 of the 4 cores and Postgres throughput fell accordingly.
- **But they get more analytics done for the same damage.** In 120 s of TPC-B, plain Postgres finished 4 Q4s;
  pg_duckdb (tuned) 8; pg_lake 50.
- **"Accelerate queries": only partly.** On live heap tables pg_duckdb was slower than stock Postgres for scans
  and simple aggregates and faster only for high-cardinality and distinct shapes. The order-of-magnitude
  speed-ups need a columnar copy (Parquet/Iceberg), i.e. a second copy of the data to keep in sync, the same
  operational shape as replicating to ClickHouse.
- **pg_clickhouse offloads compute: confirmed.** Postgres did almost no analytical work (its CPU stayed at
  baseline while ClickHouse ran at ~155%), OLTP throughput changed by −0.2% (TPC-B) and −1.8% (select-only),
  and it completed the most analytics (73 Q4s in 120 s, against 4, 8 and 50).

### Note on ClickHouse 26.10 under load

pg_clickhouse's Q4 took 563 ms on an idle host but a median ~1.56 s inside the contention loops. ClickHouse's
`system.query_log` shows that time is spent in ClickHouse, not in pg_clickhouse: Q4 durations are bimodal
(~0.4-0.6 s or ~1.4-2.9 s). An interleaved A/B on the laptop (`results/ab_ch_versions_laptop/`, scripts 09-10) showed
the same behaviour on 26.10.3.7 and not on 25.8.33.6 (steady ~0.6 s), and that it is not caused by 26.10's new
`concurrent_threads_scheduler` / `cpu_slot_preemption` defaults. It lowers pg_clickhouse's analytics
throughput in section 2, not the OLTP impact.

## 4. Qualitative findings: install friction and gotchas

| | pg_duckdb | pg_lake | pg_clickhouse |
|---|---|---|---|
| Official image | Yes (`pgduckdb/pgduckdb:17-v1.1.1`, Dec 2025) | **No prebuilt image.** Build from the repo Dockerfile | Yes (`ghcr.io/clickhouse/pg_clickhouse:17`) |
| Build / install time | image pull | ~13 min on 16 Graviton5 cores for a slimmed PG17-only build (PG + PostGIS + vcpkg Azure SDK + DuckDB compile); ~73 min on a laptop; two images ~1.8 GB each | image pull |
| `shared_preload_libraries` | `pg_duckdb` (restart) | `pg_extension_base` (restart) | not needed |
| Extra processes / infra | none (DuckDB inside each backend) | **pgduck_server** (separate DuckDB process, unix socket on a shared volume) + **object storage** (S3/GCS/Azure) | a **ClickHouse server** + a replication path (CDC in prod) |
| Superuser | needed for `duckdb.max_memory` etc. | init (`CREATE SECRET` in pgduck_server) | `CREATE SERVER` / user mapping |
| Data copy needed | no for heap (slow); yes for fast path (Parquet) | yes (Iceberg CTAS: 51 s / 50M rows) | yes (MergeTree: 28 s / 50M rows via `postgresql()`, 800 MiB compressed) |

Errors and surprises hit, as-is:
- **pg_duckdb**: default `duckdb.max_memory` (4 GB per connection) → backend OOM-kill → postmaster crash-restart of
  all connections (reproduced on the laptop and on EC2). `duckdb.force_execution=true` is required for heap
  queries, otherwise the Postgres executor runs them. The published image is PG 17.7 / pg_duckdb 1.1.1 (latest
  release, Dec 2025).
- **pg_lake**: no published image; the upstream Dockerfile compiles PG 16-19 (the PG 18/16/19 builds with
  `--enable-cassert`) plus test tooling, and recommends 16 GB+ RAM to build. The compose file's localstack S3 now
  requires an auth token (we substituted SeaweedFS). pgduck_server takes ~20-60 s after start before its socket
  accepts connections; until then queries fail with `ERROR: could not start query engine`. The schema name `lake`
  is reserved by the extension. With the upstream config the Postgres log gets a warning every second:
  `object store catalog export failed: pg_lake_iceberg.object_store_catalog_location_prefix is not set`.
- **pg_clickhouse**: the newest published image is 0.11. Docs say the binary driver defaults to port 9004 for
  non-Cloud hosts; we set `port '9000'` explicitly. `IMPORT FOREIGN SCHEMA` mapped `LowCardinality(String)` → text,
  `DateTime64(6,'UTC')` → timestamptz, `Decimal(10,2)` → numeric(10,2) without manual work. No query in this set
  fell back to local execution.

## 5. Caveats

- One host. ClickHouse runs on its own cores and memory cgroup but shares the host's memory bandwidth, kernel
  and NVMe with Postgres. A separate ClickHouse server would be more isolated, not less.
- One analytics session only. More concurrent analytical sessions would multiply pg_duckdb's per-backend
  memory (each connection gets its own DuckDB instance and `max_memory`).
- `docker stats` CPU samples are ~1-2 s apart and coarse; treat CPU% as indicative.
- The pg_lake path got 8 GiB total RAM (two cgroups) vs 4 GiB for the others; CPU was shared on the same 4 cores.
- Different Postgres builds: 17.7 (pgduckdb image, Debian 12), 17.11 (pg_clickhouse image, Debian 13), 17.11
  compiled from source on AlmaLinux 9 (pg_lake). Compare each path with its own baseline.
- Cold runs for pg_lake keep pgduck_server's on-disk file cache (by design), so they are "cold process, warm local cache".
- ClickHouse was modelled the ClickHouse way (`LowCardinality`, `ORDER BY event_time`); the Parquet/Iceberg files
  use default layouts written by DuckDB/pg_lake.

## Appendix: earlier laptop runs

The lab was first run on a MacBook (OrbStack, 14 vCPUs) with ClickHouse 25.8 (2026-10-29) and then 26.10
(2026-10-30). Those runs reached the same conclusions, but the read-write TPC-B baselines varied by up to 2× on one
instance because of the shared laptop SSD, and host load affected ClickHouse 26.10 more than 25.8. The EC2 run
above replaces them.
