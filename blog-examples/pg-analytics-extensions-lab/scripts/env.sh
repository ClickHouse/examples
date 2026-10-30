# Shared settings for every lab script. Source me.
LAB=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
NET=pglab
IMG_PGDUCKDB=pgduckdb/pgduckdb:17-v1.1.1
IMG_PGCH=ghcr.io/clickhouse/pg_clickhouse:17
IMG_PGLAKE=pg_lake:lab-pg17
IMG_PGDUCK_SERVER=pgduck-server:lab-pg17
IMG_CH=clickhouse/clickhouse-server:25.8
IMG_CLIENT=postgres:17
IMG_S3=chrislusf/seaweedfs:latest
# Resource caps. Every Postgres instance is pinned to the SAME 4 cores (0-3) and only one runs at a time
# during benchmarks. ClickHouse = "separate machine" on cores 8-11. Load generator/client on 4-7.
PG_CPUSET=0-3
CH_CPUSET=8-11
CLIENT_CPUSET=4-7
S3_CPUSET=12-13
PG_CAPS="--cpus=4 --memory=4g --memory-swap=4g --shm-size=1g"
CH_CAPS="--cpus=4 --memory=4g --memory-swap=4g --cpuset-cpus=$CH_CPUSET"
PG_FLAGS="-c shared_buffers=1GB -c work_mem=64MB -c max_parallel_workers_per_gather=4 -c max_wal_size=4GB -c maintenance_work_mem=512MB -c max_connections=100"
ROWS=${ROWS:-50000000}
psql_c() { # psql_c <container> [psql args...]  -- runs psql from the client container against <container>
  local host=$1; shift
  docker exec -i lab-client psql -X -h "$host" -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"
}
drop_os_caches() {
  docker run --rm --privileged $IMG_CLIENT sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches' >/dev/null 2>&1 || echo "WARN: drop_caches failed"
}
wait_pg() { # wait_pg <container>
  for _ in $(seq 1 120); do docker exec lab-client pg_isready -q -h "$1" -U postgres && return 0; sleep 1; done; echo "timeout waiting for $1"; return 1
}
