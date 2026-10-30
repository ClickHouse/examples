# Results: pg_duckdb vs pg_lake vs pg_clickhouse (lab run 2026-10-29)

Setup, versions and deviations: [README.md](README.md). Raw outputs: `results/`. Every Postgres instance
was capped at 4 CPUs (pinned to the same cores 0-3) and 4 GiB; ClickHouse ran in its own 4 CPU / 4 GiB container
on other cores; 50M-row events table + 5M-row users table. **Single MacBook, one run per configuration, not a
formal benchmark.**

Correctness: `scripts/compare_results.py` confirms every path returned identical results for all six queries.

## 1. Query latency (no concurrent OLTP load)

Wall-clock from `psql \timing` in a client container. Cold = path's containers restarted + VM page cache
dropped; warm = median of the next 3 runs in the same session.

#### Warm (median of runs 2-4)

| Query | plain PG | pg_duckdb (heap, defaults) | pg_duckdb (heap, tuned¹) | pg_duckdb (Parquet²) | pg_lake (Iceberg) | pg_clickhouse |
|---|---:|---:|---:|---:|---:|---:|
| Q1 count+sum | 903 ms | 2.24 s | 2.05 s | 44 ms | 124 ms | 35 ms |
| Q2 group by event_type | 1.55 s | 3.21 s | 2.86 s | 76 ms | 251 ms | 72 ms |
| Q3 country × day, 1 month | 419 ms | 608 ms | 424 ms | 93 ms | 432 ms | 35 ms |
| Q4 top-10 users (5M groups) | 21.62 s | **OOM-killed** | 4.63 s | 797 ms | 912 ms | 633 ms |
| Q5 count(DISTINCT user_id) | 8.36 s | 2.32 s | 1.91 s | 415 ms | 533 ms | 252 ms |
| Q6 join 5M users, 1 month | 1.76 s | 1.32 s | 1.01 s | 206 ms | 1.01 s | 231 ms |

#### Cold (run 1)

| Query | plain PG | pg_duckdb (defaults) | pg_duckdb (tuned¹) | pg_duckdb (Parquet²) | pg_lake | pg_clickhouse |
|---|---:|---:|---:|---:|---:|---:|
| Q1 | 7.63 s | 8.92 s | 6.16 s | 216 ms | 307 ms | 81 ms |
| Q2 | 1.72 s | 3.56 s | 3.23 s | 113 ms | 354 ms | 94 ms |
| Q3 | 930 ms | 1.06 s | 856 ms | 121 ms | 609 ms | 134 ms |
| Q4 | 16.63 s | 3.78 s | 3.12 s | 1.44 s | 1.49 s | 836 ms |
| Q5 | 11.02 s | 2.62 s | 2.08 s | 465 ms | 612 ms | 272 ms |
| Q6 | 2.57 s | 2.89 s | 1.58 s | 275 ms | 1.33 s | 289 ms |

¹ `duckdb.max_memory=2048`, `duckdb.max_workers_per_postgres_scan=4`, `duckdb.threads_for_postgres_scan=4`.
² Heap exported once to local Parquet with DuckDB `COPY … TO` (14.7 s), queried via `read_parquet` views, `duckdb.max_memory=2048`.

Pushdown (from `results/explain/`):
- **pg_clickhouse: all six queries fully pushed down** as a single `Foreign Scan` with remote SQL, including
  `count(DISTINCT)`, `date_trunc('day')` → `toStartOfDay`, `ORDER BY … LIMIT`, and the events⋈users join
  (`ALL INNER JOIN` executed in ClickHouse).
- **pg_lake: all six fully pushed down** (`Custom Scan (Query Pushdown)`, Engine: DuckDB); the time filter
  pruned Q3 to 1 of 4 data files and Q6 to 3 of 4.
- **pg_duckdb: all six run in DuckDB** (`Custom Scan (DuckDBScan)`), but the leaf is always
  `PGDUCKDB_POSTGRES_SCAN` — DuckDB reads heap tuples through Postgres (time filters are pushed into that scan).
- plain PG: parallel seq/index scans with 4 workers, except Q5 (`count(DISTINCT)` is not parallelised: single-process sort of 50M rows).

What the latency numbers say:
- **pg_duckdb on heap tables is not a universal accelerator.** It was *slower* than plain Postgres on simple
  scans/low-cardinality aggregates (Q1 2.5×, Q2 2× slower), roughly even on Q3, and faster only where Postgres
  is weak: high-cardinality aggregation (Q4 4.7× faster tuned), `count(DISTINCT)` (Q5 ~4×), and the join (Q6 1.7×).
  The bottleneck is reading row-format heap pages through the Postgres scan, not DuckDB's engine.
- **The same DuckDB on columnar data is fast.** pg_duckdb on a Parquet copy was ~4.6-47× faster than on the heap (4.6-5.8× on Q3-Q6, 38-47× on Q1-Q2)
  and within ~1-2× of ClickHouse; pg_lake (also DuckDB, over Iceberg/Parquet on S3) was similar, a bit slower
  because of the extra hop to pgduck_server and S3 reads. So the large analytical speed-ups from both DuckDB
  extensions come from *changing the storage format* (which means keeping a second copy of the data), not from
  running against the live OLTP tables.
- pg_clickhouse was the fastest path on five of six queries warm (35 ms-633 ms); on the Q6 join pg_duckdb over Parquet was ~10% faster (206 vs 231 ms warm).
- Even in the best case for the in-process approach the result needs a data copy: Parquet export (pg_duckdb),
  Iceberg CTAS (pg_lake, 61 s for 50M rows), or MergeTree replication (pg_clickhouse, 32 s one-shot load; CDC in production).

## 2. Contention: OLTP throughput while analytics runs

`pgbench -c 16 -j 4` (scale 50, `pgbench` DB in the **same** Postgres instance as the events data) with and
without one psql session looping Q3 + Q4 through each path. Δ TPS is vs the mean of that instance's baseline
runs. CPU% from `docker stats` (100% = 1 core; the Postgres containers are capped at 400%).

### 2a. TPC-B (default pgbench, read-write, 120 s)

| Run | TPS | Δ TPS | avg lat | p95 lat | p99 lat | analytics completed in 120 s (Q3 / Q4, median ms) | Postgres CPU avg | pgduck_server CPU avg | ClickHouse CPU avg |
|---|---:|---:|---:|---:|---:|---|---:|---:|---:|
| baseline pgch r1 / r2 / r3 | 3983 / 4156 / **8103** | — | 4.0 / 3.8 / 2.0 ms | 9.7 / 8.7 / 4.1 ms | 20.8 / 32.2 / 8.2 ms | — | 126% / 108% / 156% | — | 5% |
| + plain PG loop | 2270 | **-44%** (vs r1/r2) | 7.0 ms | 17.1 ms | 38.5 ms | 5 / 4 (2.9 s / 27.4 s) | 278% | — | 7% |
| + pg_clickhouse loop (r1) | 2942 | **-28%** (vs r1/r2) | 5.4 ms | 11.1 ms | 24.2 ms | 227 / 226 (32 ms / 601 ms) | 77% | — | 291% |
| + pg_clickhouse loop (r2) | 3986 | **-2%** (vs r1/r2) | 4.0 ms | 9.3 ms | 16.0 ms | 212 / 218 (32 ms / 606 ms) | 91% | — | 286% |
| baseline pgduck r1 / r2 | 5017 / 3984 | — | 3.2 / 4.0 ms | 8.1 / 9.6 ms | 16.2 / 18.0 ms | — | 140% / 113% | — | 6% |
| + pg_duckdb loop (defaults) | 2068 | **-54%, run aborted** | 7.7 ms | 17.5 ms | 87.9 ms | 2 / 1, then backend OOM-killed | 152% | — | 7% |
| + pg_duckdb loop (tuned) | 2166 | **-52%** | 7.4 ms | 17.0 ms | 36.2 ms | 16 / 15 (1.35 s / 6.7 s) | 280% | — | 7% |
| baseline pglake r1 / r2 | 5666 / 5178 | — | 2.8 / 3.1 ms | 6.2 / 6.5 ms | 11.2 / 17.4 ms | — | 126% / 118% | 0% | 6% |
| + pg_lake loop | 2372 | **-56%** | 6.7 ms | 13.4 ms | 22.6 ms | 74 / 73 (506 ms / 1.16 s) | 60% | 184% | 6% |

Run order for pgch was r1 → plain → ch → r2 → (select-only matrix) → ch r2 → r3. Δ for pgch is vs the mean of
r1/r2 (4070 TPS); **r3 came in at 8103 TPS on the same instance with nothing else running**, which shows how
noisy this fsync-bound test is on this laptop.
Raw logs: `results/contention/`.

### 2b. Select-only (pgbench -S, CPU-bound, 60 s)

| Run | TPS | Δ TPS | p95 lat | p99 lat | analytics completed in 60 s (Q3 / Q4, median ms) | Postgres CPU avg | pgduck_server CPU avg | ClickHouse CPU avg |
|---|---:|---:|---:|---:|---|---:|---:|---:|
| baseline pgch | 184,200 | — | 0.14 ms | 0.19 ms | — | 435% | — | 5% |
| + plain PG loop | 103,119 | **-44%** | 0.31 ms | 0.69 ms | 2 / 1 (4.0 s / 39.4 s) | 257% | — | 8% |
| + pg_clickhouse loop | 166,101 | **-10%** | 0.16 ms | 0.22 ms | 105 / 103 (33 ms / 625 ms) | 216% | — | 233% |
| baseline pgduck | 190,074 | — | 0.14 ms | 0.18 ms | — | 437% | — | 6% |
| + pg_duckdb loop (tuned) | 110,301 | **-42%** | 0.29 ms | 0.65 ms | 4 / 4 (2.4 s / 12.5 s) | 254% | — | 8% |
| baseline pglake | 187,176 | — | 0.14 ms | 0.18 ms | — | 438% | 0% | 6% |
| + pg_lake loop | 96,776 | **-48%** | 0.30 ms | 2.11 ms | 26 / 25 (653 ms / 1.87 s) | 138% | 102% | 8% |

### Memory behaviour

- **pg_duckdb defaults are unsafe in a 4 GiB instance.** `duckdb.max_memory` defaults to 4096 MB *per backend*,
  on top of `shared_buffers=1GB`. Q4 (5M-group hash aggregate) completed once (3.8 s) and was OOM-killed by the
  container's memory cgroup on the next run in the same session (`anon-rss ≈ 4.0 GB`). Postgres treats a
  SIGKILLed backend as a crash: the postmaster terminates **every** connection and runs crash recovery. In the
  contention run with defaults this aborted the pgbench run after ~20-25 s. With
  `duckdb.max_memory=2048` there were no OOMs, but the backend still peaked at ~3.2 GiB of the 4 GiB cap, and Q4
  got progressively slower within a session (3.1 → 3.8 → 4.6 → 5.0 s).
- pg_lake's DuckDB lives in pgduck_server with its own memory limit (default 80% of its container = 3.1 GiB),
  so analytics memory pressure never touched the Postgres cgroup (Postgres stayed at 0.86 GiB). In this lab
  pgduck_server had a separate 4 GiB cgroup; on a single real host it would share RAM with Postgres. It peaked at 2.9 GiB.
- pg_clickhouse: the Postgres container stayed at ~2 GiB (shared_buffers + pgbench) and ClickHouse used up to
  3.3 GiB in its own container. No OOMs anywhere outside the pg_duckdb default runs.

## 3. Interpretation vs the hypothesis

> "In-process extensions accelerate queries but compete with OLTP for the same CPU/RAM; pg_clickhouse offloads compute to ClickHouse."

- **Competes with OLTP: confirmed.** Both DuckDB paths cut OLTP throughput about as much as running the
  analytics on plain Postgres: −52% (pg_duckdb) and −56% (pg_lake) on TPC-B, −42% / −48% on select-only, vs
  −44% for plain Postgres. pg_lake running DuckDB in a separate process does not help when that process is on
  the same cores: pgduck_server used 1-2 of the 4 cores and Postgres throughput fell accordingly.
- **But they do get far more analytics done for the same damage.** In 120 s of TPC-B, plain Postgres finished
  4 Q4s; pg_duckdb (tuned) 15; pg_lake 73. The DuckDB paths convert the stolen CPU into much more analytical
  work, which matters when comparing them against plain Postgres.
- **"Accelerate queries": only partly.** On live heap tables pg_duckdb was slower than stock Postgres for scans and
  simple aggregates and faster only for high-cardinality/distinct/join shapes. The order-of-magnitude speed-ups
  need a columnar copy (Parquet/Iceberg), i.e. a second copy of the data to keep in sync, the same operational
  shape as replicating to ClickHouse.
- **pg_clickhouse offloads compute: confirmed, with a caveat.** Postgres did almost no analytical work
  (CPU stayed at or below baseline while ClickHouse ran at ~230-290%), it completed by far the most analytics
  (226 Q4s in 120 s at ~600 ms each), and in the CPU-bound select-only test OLTP throughput dropped only 10% vs
  42-48% for the in-process paths. **The caveat:** in the fsync-bound TPC-B test the pg_clickhouse result was
  not stable across two runs: −28% and −2%, against baselines that themselves ranged
  from 3983 to 8103 TPS. Because Postgres CPU stayed at or below baseline during those runs, the residual impact comes from sharing one laptop (same SSD, VM kernel, memory
  bandwidth, and the Apple-silicon CPU package), not from Postgres executing the queries. On a genuinely
  separate ClickHouse host that shared-hardware component would not exist. We cannot prove that from this lab, only
  infer it from the CPU data.

## 4. Qualitative findings: install friction and gotchas

| | pg_duckdb | pg_lake | pg_clickhouse |
|---|---|---|---|
| Official image | Yes (`pgduckdb/pgduckdb:17-v1.1.1`, Dec 2025) | **No prebuilt image.** Build from the repo Dockerfile | Yes (`ghcr.io/clickhouse/pg_clickhouse:17`) |
| Build / install time here | image pull | ~31 min of a full upstream build (mostly `dnf`; downloads were slow) before restarting with a slimmed PG17-only Dockerfile, which then took ~42 min (PG + PostGIS + vcpkg Azure SDK + DuckDB compile); two images ~1.8 GB each | image pull |
| `shared_preload_libraries` | `pg_duckdb` (restart) | `pg_extension_base` (restart) | not needed |
| Extra processes / infra | none (DuckDB inside each backend) | **pgduck_server** (separate DuckDB process, unix socket on a shared volume) + **object storage** (S3/GCS/Azure) | a **ClickHouse server** + a replication path (ClickPipes/CDC in prod) |
| Superuser | needed for `duckdb.max_memory` etc. | init (`CREATE SECRET` in pgduck_server) | `CREATE SERVER` / user mapping |
| Data copy needed | no for heap (slow); yes for fast path (Parquet) | yes (Iceberg CTAS: 61 s / 50M rows, 1.5 GB Parquet) | yes (MergeTree: 32 s / 50M rows via `postgresql()`, 1.4 GiB compressed) |

Errors and surprises hit, as-is:
- **pg_duckdb**: default `duckdb.max_memory` (4 GB per connection) → backend OOM-kill → postmaster crash-restart of
  all connections (reproduced twice). `duckdb.force_execution=true` is required for heap queries, otherwise the
  Postgres executor runs them. DuckDB detected the 4-CPU cgroup correctly (`threads=4`). The published image is
  PG 17.7 / pg_duckdb 1.1.1 (latest release, Dec 2025).
- **pg_lake**: no published image; the upstream Dockerfile compiles PG 16-19 (the PG 18/16/19 builds with
  `--enable-cassert`) plus test tooling (Java, Node/azurite, Polaris submodule), and recommends 16 GB+ RAM to build.
  The compose file's localstack S3 now requires an auth token (we substituted SeaweedFS). pgduck_server takes
  ~20-60 s after start before its socket accepts connections; until then queries fail with
  `ERROR: could not start query engine`. The schema name `lake` is reserved by the extension
  (`cannot drop schema lake because extension pg_lake requires it`). With the upstream config the Postgres log gets a
  warning every second: `object store catalog export failed: pg_lake_iceberg.object_store_catalog_location_prefix is not set`.
- **pg_clickhouse**: the newest published image is 0.11 while repo `main` is 0.12.0 (unreleased). Docs say the
  binary driver defaults to port 9004 for non-Cloud hosts; we set `port '9000'` explicitly. `IMPORT FOREIGN SCHEMA`
  mapped `LowCardinality(String)` → text, `DateTime64(6,'UTC')` → timestamptz, `Decimal(10,2)` → numeric(10,2)
  without manual work. No query in this set fell back to local execution.
- No unsupported types/queries were hit on any path for this schema and these six queries.

## 5. Caveats

- One laptop, one VM, cgroup caps. ClickHouse "on a separate machine" shares the SSD, kernel page cache,
  memory bandwidth and CPU package with Postgres. This *understates* the isolation of a real separate host.
- pgbench TPC-B here is commit/fsync-bound (Postgres at ~1.1-1.4 of 4 cores at baseline), so it measures more
  than CPU contention. Baselines varied 20% between back-to-back runs (pgduck 5017 vs 3984 TPS) and up to 2× on
  one instance (pgch 3983 / 4156 / 8103 TPS), so differences under about 30% in 2a are within noise. The DuckDB and plain-PG
  drops (−44% to −56%) repeated consistently across runs; the pg_clickhouse TPC-B numbers did not. The select-only test (2b) is the cleaner CPU-contention signal.
- One analytics session only. More concurrent analytical sessions would multiply pg_duckdb's per-backend
  memory (each connection gets its own DuckDB instance and `max_memory`).
- `docker stats` CPU samples are ~1-2 s apart and coarse; treat CPU% as indicative.
- The pg_lake path got 8 GiB total RAM (two cgroups) vs 4 GiB for the others; CPU was shared on the same 4 cores.
- The query-latency runs for plain/pg_clickhouse/pg_duckdb were taken while the pg_lake image was building on
  other cores (cores 8-13, or 4-13; never 0-3). The contention tables in section 2 were all taken after the build finished.
- Different Postgres builds: 17.7 (pgduckdb image, Debian 12), 17.11 (pg_clickhouse image, Debian 13), 17.11
  compiled from source on AlmaLinux 9 (pg_lake). Baseline TPS differs by instance, so compare each path with its own baseline.
- Cold runs for pg_lake keep pgduck_server's on-disk file cache (by design), so they are "cold process, warm local cache".
- ClickHouse was modelled the ClickHouse way (`LowCardinality`, `ORDER BY event_time`); the Parquet/Iceberg files
  use default layouts written by DuckDB/pg_lake.
