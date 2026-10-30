#!/usr/bin/env bash
# Usage: 03_bench_queries.sh <path> [Q1 Q2 ...]
# Per query:
#  - COLD_RUNS (default 10) cold runs: before each, restart the path's containers and drop the OS page cache
#    (cold_reset in paths.sh; for pg_lake also empties pgduck_server's file cache; object storage keeps running),
#    then run the query once in a new session.
#  - WARM_RUNS (default 10) warm runs: one session, one untimed warm-up run (for pg_lake, then wait for the file
#    cache to hold the files), then WARM_RUNS timed runs.
# Wall-clock from psql \timing (client side). Appends to results/queries/timings.csv (path,query,mode,run,ms,ts).
set -euo pipefail
source "$(dirname "$0")/env.sh"; source "$(dirname "$0")/paths.sh"
P=$1; shift; QS=${*:-Q1 Q2 Q3 Q4 Q5 Q6}; COLD_RUNS=${COLD_RUNS:-10}; WARM_RUNS=${WARM_RUNS:-10}
H=$(path_host $P); OUT=$LAB/results/queries/$P; mkdir -p $OUT
CSV=$LAB/results/queries/timings.csv; [ -f $CSV ] || echo "path,query,mode,run,ms,ts" > $CSV
run_psql() { # run_psql <input> <output>; tolerate failures (e.g. an OOM-killed backend), log them
  set +e; docker exec -i lab-client timeout 1800 psql -X -h $H -U postgres -d postgres -f - < $1 > $2 2>&1; local rc=$?; set -e
  [ $rc -ne 0 ] && echo "$P $Q $(basename $2) psql rc=$rc" | tee -a $OUT/errors.log; return 0
}
for Q in $QS; do
  SQL=$(cat $LAB/sql/queries/$Q.sql); TS=$(date +%s)
  # cold
  for r in $(seq 1 $COLD_RUNS); do
    cold_reset $P
    { echo "$(path_setup $P)"; echo "\\timing on"; echo "\\echo RUN 1"; echo "$SQL"; } > $OUT/$Q.cold.input.sql
    run_psql $OUT/$Q.cold.input.sql $OUT/$Q.cold$r.out
    awk -v p=$P -v q=$Q -v r=$r -v ts=$TS '/^Time: /{print p","q",cold,"r","$2","ts}' $OUT/$Q.cold$r.out | tail -1 >> $CSV
  done
  # warm (container state left by the last cold run: same process, caches now populated)
  wait_ready $P
  { echo "$(path_setup $P)"; echo "\\timing on"; echo "\\echo WARMUP"; echo "$SQL"; } > $OUT/$Q.warmup.input.sql
  run_psql $OUT/$Q.warmup.input.sql $OUT/$Q.warmup.out
  if [ "$P" = lake ]; then wait_lake_cache; fi
  { echo "$(path_setup $P)"; echo "\\timing on"; for r in $(seq 1 $WARM_RUNS); do echo "\\echo RUN $r"; echo "$SQL"; done; } > $OUT/$Q.input.sql
  run_psql $OUT/$Q.input.sql $OUT/$Q.out
  awk -v p=$P -v q=$Q -v ts=$TS '/^RUN /{r=$2} /^Time: /{print p","q",warm,"r","$2","ts}' $OUT/$Q.out >> $CSV
  cold=$(awk -F, -v p=$P -v q=$Q -v ts=$TS '$1==p&&$2==q&&$3=="cold"&&$6==ts{print $5}' $CSV | sort -n | awk '{a[NR]=$1} END{print (NR?a[int((NR+1)/2)]:"-")}')
  warm=$(awk -F, -v p=$P -v q=$Q -v ts=$TS '$1==p&&$2==q&&$3=="warm"&&$6==ts{print $5}' $CSV | sort -n | awk '{a[NR]=$1} END{print (NR?a[int((NR+1)/2)]:"-")}')
  echo "$P $Q: cold median ${cold} ms, warm median ${warm} ms"
done
