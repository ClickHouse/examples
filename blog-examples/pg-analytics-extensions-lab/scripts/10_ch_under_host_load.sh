#!/usr/bin/env bash
# Q4 straight into ClickHouse (clickhouse-benchmark, no pg_clickhouse) while pgbench -S loads the Postgres cores.
# Usage: 10_ch_under_host_load.sh <image> <volume>
set -uo pipefail
source "$(dirname "$0")/env.sh"
IMG=$1; VOL=$2; OUT=$LAB/results/ab_ch_versions; Q="$(sed -n 2p $OUT/queries.sql)"
docker rm -f lab-ch >/dev/null 2>&1
docker run -d --name lab-ch --network $NET $CH_CAPS --ulimit nofile=262144:262144 -e CLICKHOUSE_USER=default \
  -e CLICKHOUSE_PASSWORD=lab -e CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT=1 -v $VOL:/var/lib/clickhouse $IMG >/dev/null
for _ in $(seq 60); do docker exec lab-ch clickhouse-client --password lab -q "select 1" >/dev/null 2>&1 && break; sleep 1; done
V=$(docker exec lab-ch clickhouse-client --password lab -q "select version()")
B="--join_use_nulls=1 --group_by_use_nulls=1 --final=1"
idle=$(docker exec lab-ch clickhouse-benchmark --password lab -i 20 -c 1 $B --query "$Q" 2>&1 | awk '/^50/{print $2}')
docker exec lab-client pgbench -S -h lab-pgch -U postgres -c 16 -j 4 -T 70 pgbench > $OUT/hostload_${V}_pgbench.log 2>&1 &
PB=$!; sleep 5
busy=$(docker exec lab-ch clickhouse-benchmark --password lab -i 20 -c 1 $B --query "$Q" 2>&1 | awk '/^50/{print $2}')
wait $PB
echo "$V Q4 median: idle ${idle}s, during pgbench -S ${busy}s, pgbench $(grep -o 'tps = [0-9.]*' $OUT/hostload_${V}_pgbench.log | head -1)"
