#!/usr/bin/env bash
# Latency suite with COLD_RUNS/WARM_RUNS (default 10/10) for every path, then the pg_lake contention runs again
# (needed after the pgduck_server cache-directory permission fix). Other contention results are unchanged.
set -uo pipefail
source "$(dirname "$0")/env.sh"; source "$(dirname "$0")/paths.sh"
S=$(dirname "$0"); step() { echo "### $(date -u +%H:%M:%S) $*"; }
docker start lab-pgch lab-ch lab-pgduck lab-s3 lab-pgduck-server lab-pglake >/dev/null
for p in plain ch duckdb duckdb_tuned duckdb_parquet lake; do step "latency $p"; $S/03_bench_queries.sh $p; done
for p in plain ch duckdb lake; do $S/04_explain.sh $p; done
step "compare"; python3 $S/compare_results.py
# pg_lake contention with a working file cache: fill the cache first
for c in lab-pgch lab-pgduck lab-ch; do docker stop $c >/dev/null; done
wait_ready lake
psql_c lab-pglake -c "SET search_path = ice, public" -f /lab/sql/queries/Q3.sql -f /lab/sql/queries/Q4.sql >/dev/null; wait_lake_cache
step "pg_lake contention TPC-B"
$S/05_contention.sh pglake none 120 r1; $S/05_contention.sh pglake lake; $S/05_contention.sh pglake none 120 r2
step "pg_lake contention select-only"
PGBENCH_ARGS=-S CONTENTION_DIR=contention_select_only $S/05_contention.sh pglake none 60
PGBENCH_ARGS=-S CONTENTION_DIR=contention_select_only $S/05_contention.sh pglake lake 60
step "ALL_DONE"
