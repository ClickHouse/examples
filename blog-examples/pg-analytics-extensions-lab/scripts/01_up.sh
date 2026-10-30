#!/usr/bin/env bash
# Start lab containers. Usage: 01_up.sh [client|ch|pgduck|pgch|pglake|all]
set -euo pipefail
source "$(dirname "$0")/env.sh"
docker network inspect $NET >/dev/null 2>&1 || docker network create $NET >/dev/null
what=${1:-all}
up_client() {
  docker rm -f lab-client >/dev/null 2>&1 || true
  docker run -d --name lab-client --network $NET --cpuset-cpus=$CLIENT_CPUSET -e PGPASSWORD=lab \
    -v "$LAB/sql:/lab/sql:ro" -v "$LAB/results:/lab/results" --entrypoint sleep $IMG_CLIENT infinity >/dev/null
}
up_ch() {
  docker rm -f lab-ch >/dev/null 2>&1 || true
  docker run -d --name lab-ch --network $NET $CH_CAPS --ulimit nofile=262144:262144 \
    -e CLICKHOUSE_USER=default -e CLICKHOUSE_PASSWORD=lab -e CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT=1 \
    -v lab-ch-data:/var/lib/clickhouse $IMG_CH >/dev/null
}
up_pgduck() {
  docker rm -f lab-pgduck >/dev/null 2>&1 || true
  docker run -d --name lab-pgduck --network $NET $PG_CAPS --cpuset-cpus=${CPUSET:-$PG_CPUSET} -e POSTGRES_PASSWORD=lab \
    -v lab-pgduck-data:/var/lib/postgresql/data $IMG_PGDUCKDB postgres $PG_FLAGS -c shared_preload_libraries=pg_duckdb >/dev/null
}
up_pgch() {
  docker rm -f lab-pgch >/dev/null 2>&1 || true
  docker run -d --name lab-pgch --network $NET $PG_CAPS --cpuset-cpus=${CPUSET:-$PG_CPUSET} -e POSTGRES_PASSWORD=lab \
    -v lab-pgch-data:/var/lib/postgresql/data $IMG_PGCH postgres $PG_FLAGS >/dev/null
}
up_pglake() {
  # Mirrors vendor/pg_lake/docker/docker-compose.yml (two containers sharing the unix-socket + tmp volumes),
  # but with SeaweedFS standing in for localstack, and both pg_lake containers pinned to the
  # SAME 4 cores so pgduck_server competes with Postgres exactly as it would on one host.
  for c in lab-pglake lab-pgduck-server lab-s3; do docker rm -f $c >/dev/null 2>&1 || true; done
  # S3: upstream compose uses localstack; localstack:latest now needs an auth token and MinIO images are no
  # longer on Docker Hub, so we use SeaweedFS's S3 gateway on the same alias/port (localstack:4566) so the
  # upstream init-pgduck-server.sql secret works unchanged.
  docker run -d --name lab-s3 --network $NET --network-alias localstack --cpuset-cpus=$S3_CPUSET --memory=3g     -v lab-s3-data:/data $IMG_S3 server -dir=/data -s3 -s3.port=4566 >/dev/null
  set +eo pipefail; sleep 5
  for _ in $(seq 1 60); do
    docker exec lab-s3 sh -c 'echo s3.bucket.list | timeout 10 weed shell 2>/dev/null' | grep -q testbucket && break
    docker exec lab-s3 sh -c 'echo "s3.bucket.create -name testbucket" | timeout 10 weed shell' >/dev/null 2>&1; sleep 2
  done; set -eo pipefail
  docker run -d --name lab-pgduck-server --network $NET --cpus=4 --memory=4g --memory-swap=4g --cpuset-cpus=${CPUSET:-$PG_CPUSET} \
    -v "$LAB/vendor/pg_lake/docker/scripts/entrypoint-pgduck-server.sh:/entrypoint-pgduck-server.sh" \
    -v "$LAB/vendor/pg_lake/docker/scripts/init-pgduck-server.sql:/init-pgduck-server.sql" \
    -v lab-pglake-sock:/home/postgres/pgduck_socket_dir -v lab-pglake-tmp:/home/postgres/pgsql-17/data/base/pgsql_tmp \
    -v lab-pglake-cache:/home/postgres/cache \
    -e PG_MAJOR=17 --entrypoint /entrypoint-pgduck-server.sh $IMG_PGDUCK_SERVER >/dev/null
  docker run -d --name lab-pglake --network $NET $PG_CAPS --cpuset-cpus=${CPUSET:-$PG_CPUSET} \
    -v "$LAB/docker/entrypoint-pglake.sh:/entrypoint-postgres.sh" \
    -v "$LAB/vendor/pg_lake/docker/scripts/init-postgres.sql:/init-postgres.sql" \
    -v lab-pglake-sock:/home/postgres/pgduck_socket_dir -v lab-pglake-tmp:/home/postgres/pgsql-17/data/base/pgsql_tmp \
    -v lab-pglake-data:/home/postgres/pgsql-17/data \
    -e PG_MAJOR=17 --entrypoint /entrypoint-postgres.sh $IMG_PGLAKE >/dev/null
}
case $what in
  client) up_client;; ch) up_ch;; pgduck) up_pgduck;; pgch) up_pgch;; pglake) up_pglake;;
  all) up_client; up_ch; up_pgduck; up_pgch;;
esac
docker ps --format '{{.Names}}\t{{.Status}}' | grep lab- || true
