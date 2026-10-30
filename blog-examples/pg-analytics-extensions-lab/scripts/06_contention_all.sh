#!/usr/bin/env bash
# Full contention matrix, one Postgres instance at a time, baseline before AND after the loaded runs.
set -uo pipefail
source "$(dirname "$0")/env.sh"
S=$(dirname "$0")
for c in lab-pgduck lab-pglake lab-pgduck-server lab-s3; do docker stop $c >/dev/null 2>&1; done
docker start lab-pgch lab-ch >/dev/null; wait_pg lab-pgch
$S/05_contention.sh pgch none 120 r1; $S/05_contention.sh pgch plain; $S/05_contention.sh pgch ch; $S/05_contention.sh pgch none 120 r2
docker stop lab-pgch >/dev/null; docker start lab-pgduck >/dev/null; wait_pg lab-pgduck
$S/05_contention.sh pgduck none 120 r1; $S/05_contention.sh pgduck duckdb; $S/05_contention.sh pgduck duckdb_tuned; $S/05_contention.sh pgduck none 120 r2
docker stop lab-pgduck >/dev/null; docker start lab-s3 lab-pgduck-server lab-pglake >/dev/null; wait_pg lab-pglake; sleep 5
$S/05_contention.sh pglake none 120 r1; $S/05_contention.sh pglake lake; $S/05_contention.sh pglake none 120 r2
