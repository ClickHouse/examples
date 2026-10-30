#!/usr/bin/env bash
# Rebuild the pg_clickhouse instance + ClickHouse (IMG_CH) and rerun only the pg_clickhouse measurements:
# load, query latency, EXPLAIN, TPC-B contention matrix and select-only contention matrix.
set -uo pipefail
source "$(dirname "$0")/env.sh"
S=$(dirname "$0")
docker pull -q $IMG_CH
$S/01_up.sh client; $S/01_up.sh ch; $S/01_up.sh pgch
wait_pg lab-pgch
for _ in $(seq 1 60); do docker exec lab-ch clickhouse-client --password lab -q "select version()" 2>/dev/null && break; sleep 1; done
$S/02_gen_events.sh lab-pgch
$S/02_init_pgbench.sh lab-pgch
$S/02_load_clickhouse.sh > $LAB/results/load/clickhouse_load.log 2>&1; tail -20 $LAB/results/load/clickhouse_load.log
grep -v '^ch,' $LAB/results/queries/timings.csv > $LAB/results/queries/timings.tmp && mv $LAB/results/queries/timings.tmp $LAB/results/queries/timings.csv
rm -rf $LAB/results/queries/ch
$S/03_bench_queries.sh ch
$S/04_explain.sh ch
python3 $S/compare_results.py
$S/05_contention.sh pgch none 120 r1; $S/05_contention.sh pgch plain; $S/05_contention.sh pgch ch
$S/05_contention.sh pgch none 120 r2; $S/05_contention.sh pgch ch 120 r2; $S/05_contention.sh pgch none 120 r3
export PGBENCH_ARGS=-S CONTENTION_DIR=contention_select_only
$S/05_contention.sh pgch none 60; $S/05_contention.sh pgch plain 60; $S/05_contention.sh pgch ch 60
echo RERUN_DONE
