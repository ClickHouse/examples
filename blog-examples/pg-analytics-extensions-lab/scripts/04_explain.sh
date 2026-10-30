#!/usr/bin/env bash
# Usage: 04_explain.sh <path>  -- capture EXPLAIN (VERBOSE) for every query on a path.
set -euo pipefail
source "$(dirname "$0")/env.sh"; source "$(dirname "$0")/paths.sh"
P=$1; H=$(path_host $P); OUT=$LAB/results/explain; mkdir -p $OUT; : > $OUT/$P.txt
for Q in Q1 Q2 Q3 Q4 Q5 Q6; do
  { echo "===== $Q: $(cat $LAB/sql/queries/$Q.sql)"; } >> $OUT/$P.txt
  { echo "$(path_setup $P)"; echo "EXPLAIN (VERBOSE) $(cat $LAB/sql/queries/$Q.sql)"; } | \
    docker exec -i lab-client psql -X -h $H -U postgres -d postgres -f - >> $OUT/$P.txt 2>&1 || true
done
echo "wrote $OUT/$P.txt"
