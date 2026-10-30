#!/usr/bin/env bash
# CPU-bound variant: pgbench select-only (-S), 60 s, same analytics loops. Results in results/contention_select_only/
set -uo pipefail
source "$(dirname "$0")/env.sh"
S=$(dirname "$0"); export PGBENCH_ARGS=-S CONTENTION_DIR=contention_select_only
for c in lab-pgduck lab-pglake lab-pgduck-server lab-s3; do docker stop $c >/dev/null 2>&1; done
docker start lab-pgch lab-ch >/dev/null; wait_pg lab-pgch
$S/05_contention.sh pgch none 60; $S/05_contention.sh pgch plain 60; $S/05_contention.sh pgch ch 60
docker stop lab-pgch >/dev/null; docker start lab-pgduck >/dev/null; wait_pg lab-pgduck
$S/05_contention.sh pgduck none 60; $S/05_contention.sh pgduck duckdb_tuned 60
docker stop lab-pgduck >/dev/null; docker start lab-s3 lab-pgduck-server lab-pglake >/dev/null; wait_pg lab-pglake
$S/05_contention.sh pglake none 60; $S/05_contention.sh pglake lake 60
