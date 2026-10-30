#!/usr/bin/env bash
# Usage: 03_bench_queries.sh <path> [Q1 Q2 ...]
# For each query: restart the path's containers + drop the VM page cache (cold), then in ONE psql session run
# the query 4 times (run 1 = cold, runs 2-4 = warm). Wall-clock from psql \timing (client side).
set -euo pipefail
source "$(dirname "$0")/env.sh"; source "$(dirname "$0")/paths.sh"
P=$1; shift; QS=${*:-Q1 Q2 Q3 Q4 Q5 Q6}
H=$(path_host $P); OUT=$LAB/results/queries/$P; mkdir -p $OUT
CSV=$LAB/results/queries/timings.csv; [ -f $CSV ] || echo "path,query,run,ms,ts" > $CSV
for Q in $QS; do
  for c in $(path_containers $P); do docker restart $c >/dev/null; done
  drop_os_caches
  wait_pg $H
  if [ "$P" = lake ]; then  # pgduck_server takes ~60 s after start before its unix socket appears
    for _ in $(seq 1 180); do docker exec lab-pgduck-server psql -X -q -p 5332 -h /home/postgres/pgduck_socket_dir -c "select 1" >/dev/null 2>&1 && break; sleep 1; done; sleep 2
  fi
  [ "$P" = ch ] && for _ in $(seq 1 60); do docker exec lab-ch clickhouse-client --password lab -q "select 1" >/dev/null 2>&1 && break; sleep 1; done
  SQL=$(cat $LAB/sql/queries/$Q.sql)
  {
    echo "$(path_setup $P)"
    echo "\\timing on"
    for r in 1 2 3 4; do echo "\\echo RUN $r"; echo "$SQL"; done
  } > $OUT/$Q.input.sql
  set +e
  docker exec -i lab-client timeout 900 psql -X -h $H -U postgres -d postgres -f - < $OUT/$Q.input.sql > $OUT/$Q.out 2>&1
  rc=$?; set -e
  [ $rc -ne 0 ] && echo "$P $Q psql rc=$rc" | tee -a $OUT/errors.log
  awk -v p=$P -v q=$Q -v ts=$(date +%s) '/^RUN /{r=$2} /^Time: /{print p","q","r","$2","ts}' $OUT/$Q.out >> $CSV
  echo "$P $Q: $(awk '/^Time: /{printf "%s ", $2}' $OUT/$Q.out) ms"
  grep -m3 "ERROR" $OUT/$Q.out || true
done
