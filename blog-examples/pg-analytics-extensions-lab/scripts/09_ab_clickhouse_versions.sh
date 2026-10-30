#!/usr/bin/env bash
# A/B ClickHouse versions under identical host conditions. For each image in order: start it as lab-ch on its own
# volume, load the same data from lab-pgch, run each pushed-down query 20x with clickhouse-benchmark (using
# pg_clickhouse 0.11's default session settings), then one select-only contention run through pg_clickhouse.
# Usage: 09_ab_clickhouse_versions.sh <image> [<image> ...]
set -uo pipefail
source "$(dirname "$0")/env.sh"
S=$(dirname "$0"); OUT=$LAB/results/ab_ch_versions; mkdir -p $OUT
SETTINGS="--join_use_nulls=1 --group_by_use_nulls=1 --final=1 --transform_null_in=0"
i=0
for IMG in "$@"; do
  i=$((i+1)); V=${IMG##*:}; TAG=${i}_ch${V}
  docker rm -f lab-ch >/dev/null 2>&1; docker volume rm -f lab-ch-ab-$i >/dev/null 2>&1
  docker run -d --name lab-ch --network $NET $CH_CAPS --ulimit nofile=262144:262144 \
    -e CLICKHOUSE_USER=default -e CLICKHOUSE_PASSWORD=lab -e CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT=1 \
    -v lab-ch-ab-$i:/var/lib/clickhouse $IMG >/dev/null
  for _ in $(seq 1 60); do docker exec lab-ch clickhouse-client --password lab -q "select 1" >/dev/null 2>&1 && break; sleep 1; done
  echo "== $TAG $(docker exec lab-ch clickhouse-client --password lab -q 'select version()')"
  $S/02_load_clickhouse.sh > $OUT/${TAG}_load.log 2>&1
  n=0
  while IFS= read -r q; do
    n=$((n+1))
    docker exec lab-ch clickhouse-benchmark --password lab -i 20 -c 1 $SETTINGS --query "$q" > $OUT/${TAG}_bench_q$n.txt 2>&1
    echo "$TAG q$n $(grep -E '^50(\.000)?%' $OUT/${TAG}_bench_q$n.txt | awk '{print $2}') s median :: ${q:0:60}"
  done < $OUT/queries.sql
  PGBENCH_ARGS=-S CONTENTION_DIR=ab_ch_versions/contention $S/05_contention.sh pgch ch 60 $TAG | grep -E '"tps"|loop_q|cpu_avg'
done
PGBENCH_ARGS=-S CONTENTION_DIR=ab_ch_versions/contention $S/05_contention.sh pgch none 60 baseline_end | grep -E "\"tps\""
echo AB_DONE
