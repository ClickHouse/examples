#!/usr/bin/env bash
# Usage: 05_contention.sh <instance:pgch|pgduck|pglake> <analytics path: none|plain|ch|duckdb|lake> [duration_s]
# Runs pgbench (TPC-B-like by default, or select-only with PGBENCH_ARGS=-S; scale 50, -c16 -j4) against the instance's `pgbench` database while (optionally)
# a single psql session loops Q3+Q4 through the given analytics path. Samples docker stats every ~1s.
set -euo pipefail
source "$(dirname "$0")/env.sh"; source "$(dirname "$0")/paths.sh"
INST=$1; P=$2; DUR=${3:-120}; SUFFIX=${4:-}
H=lab-$INST; TAG=${INST}_${P}${SUFFIX:+_$SUFFIX}; OUT=$LAB/results/${CONTENTION_DIR:-contention}/$TAG; rm -rf $OUT; mkdir -p $OUT
CONTAINERS="$H lab-ch"; [ $INST = pglake ] && CONTAINERS="lab-pglake lab-pgduck-server lab-ch"
# make sure the instance accepts connections (a previous run may have crashed it into recovery)
for _ in $(seq 1 120); do psql_c $H -d pgbench -c 'select 1' >/dev/null 2>&1 && break; sleep 1; done
if [ $INST = pglake ]; then  # pgduck_server needs ~60 s after start before its socket appears
  for _ in $(seq 1 180); do docker exec lab-pgduck-server psql -X -q -p 5332 -h /home/postgres/pgduck_socket_dir -c "select 1" >/dev/null 2>&1 && break; sleep 1; done
fi
if [ $INST = pglake ] && [ "$P" = lake ]; then  # fill pgduck_server's file cache first, as a long-running server would have it
  psql_c lab-pglake -c "SET search_path = ice, public" -f /lab/sql/queries/Q3.sql -f /lab/sql/queries/Q4.sql >/dev/null; wait_lake_cache
fi
# warm-up (not measured) so shared_buffers holds the pgbench working set
docker exec lab-client pgbench ${PGBENCH_ARGS:-} -h $H -U postgres -c 16 -j 4 -T 15 pgbench > $OUT/warmup.log 2>&1
psql_c $H -d pgbench -c "CHECKPOINT" >/dev/null
START_TS=$(date +%s)
# docker stats sampler
( while true; do docker stats --no-stream --format '{{.Name}},{{.CPUPerc}},{{.MemUsage}}' $CONTAINERS | sed "s/^/$(date +%s),/"; done ) > $OUT/docker_stats.csv 2>/dev/null &
STATS=$!
LOOP=""
if [ "$P" != none ]; then
  { echo "$(path_setup $P)"; echo "\\timing on"
    for i in $(seq 1 2000); do echo "\\echo ITER $i Q3"; cat $LAB/sql/queries/Q3.sql; echo "\\echo ITER $i Q4"; cat $LAB/sql/queries/Q4.sql; done
  } > $OUT/analytics_loop.sql
  docker exec -i lab-client psql -X -h $(path_host $P) -U postgres -d postgres -f - < $OUT/analytics_loop.sql > $OUT/analytics_loop.out 2>&1 &
  LOOP=$!
  sleep 5
fi
docker exec lab-client mkdir -p /lab/results/${CONTENTION_DIR:-contention}/$TAG/pgbench_log
docker exec -w /lab/results/${CONTENTION_DIR:-contention}/$TAG/pgbench_log lab-client pgbench ${PGBENCH_ARGS:-} -h $H -U postgres -c 16 -j 4 -T $DUR -P 10 \
  -l --sampling-rate=0.05 pgbench > $OUT/pgbench.log 2>&1 || echo "pgbench rc=$?" >> $OUT/pgbench.log
if [ -n "$LOOP" ]; then
  docker exec lab-client pkill -f "psql -X -h $(path_host $P)" || true; wait $LOOP 2>/dev/null || true
fi
kill $STATS 2>/dev/null || true; wait $STATS 2>/dev/null || true
docker logs --since $START_TS $H 2>&1 | grep -E 'terminated by signal|out of memory|OOM|recovery in progress' > $OUT/server_crash_log.txt || true
# summarise
python3 "$LAB/scripts/summarise_contention.py" "$OUT" | tee $OUT/summary.txt
