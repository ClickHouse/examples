#!/usr/bin/env bash
# Full lab run on a dedicated host: load (overlapping the pg_lake build is fine; nothing is measured), then wait
# for the build to finish and run every measurement with the host otherwise idle.
set -uo pipefail
source "$(dirname "$0")/env.sh"
S=$(dirname "$0"); step() { echo "### $(date -u +%H:%M:%S) $*"; }
step "up client/ch/pgduck/pgch"; $S/01_up.sh all; wait_pg lab-pgch; wait_pg lab-pgduck
for _ in $(seq 60); do docker exec lab-ch clickhouse-client --password lab -q "select version()" 2>/dev/null && break; sleep 1; done
for c in lab-pgch lab-pgduck; do step "load $c"; $S/02_gen_events.sh $c; $S/02_init_pgbench.sh $c; done
step "load clickhouse"; $S/02_load_clickhouse.sh > $LAB/results/load/clickhouse_load.log 2>&1; grep -E "rows|real|^[0-9]" $LAB/results/load/clickhouse_load.log | head
step "parquet export"; psql_c lab-pgduck -f /lab/sql/duckdb_parquet_setup.sql > $LAB/results/load/pgduck_parquet_export.log 2>&1; tail -3 $LAB/results/load/pgduck_parquet_export.log
step "waiting for pg_lake build"
while pgrep -f "docker build" >/dev/null; do sleep 20; done
cat $LAB/results/build/build_driver.log
docker image inspect pg_lake:lab-pg17 pgduck-server:lab-pg17 >/dev/null || { echo "BUILD_FAILED"; exit 1; }
step "up pglake"; $S/01_up.sh pglake; wait_pg lab-pglake
for _ in $(seq 180); do docker exec lab-pgduck-server psql -X -q -p 5332 -h /home/postgres/pgduck_socket_dir -c "select 1" >/dev/null 2>&1 && break; sleep 1; done
step "load pglake"; $S/02_gen_events.sh lab-pglake; $S/02_init_pgbench.sh lab-pglake
( time psql_c lab-pglake -f /lab/sql/pglake_setup.sql ) > $LAB/results/load/pglake_iceberg_load.log 2>&1; tail -4 $LAB/results/load/pglake_iceberg_load.log
rm -f $LAB/results/queries/timings.csv
for p in plain ch duckdb duckdb_tuned duckdb_parquet lake; do step "latency $p"; $S/03_bench_queries.sh $p; done
for p in plain ch duckdb lake; do $S/04_explain.sh $p; done
step "compare"; python3 $S/compare_results.py
step "contention TPC-B"; $S/06_contention_all.sh 2>&1 | grep -E '"run"|"tps"|loop_q4_n|loop_errors|backend_sigkills'
step "contention select-only"; $S/07_contention_select_only.sh 2>&1 | grep -E '"run"|"tps"|loop_q4_n|loop_errors|backend_sigkills'
step "ALL_DONE"
