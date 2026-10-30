#!/usr/bin/env bash
# Start only the pg_lake Postgres container (used to load heap data while pgduck_server was still building).
set -euo pipefail
source "$(dirname "$0")/env.sh"
docker rm -f lab-pglake >/dev/null 2>&1 || true
docker run -d --name lab-pglake --network $NET $PG_CAPS --cpuset-cpus=$PG_CPUSET \
  -v "$LAB/docker/entrypoint-pglake.sh:/entrypoint-postgres.sh" \
  -v "$LAB/vendor/pg_lake/docker/scripts/init-postgres.sql:/init-postgres.sql" \
  -v lab-pglake-sock:/home/postgres/pgduck_socket_dir -v lab-pglake-tmp:/home/postgres/pgsql-17/data/base/pgsql_tmp \
  -v lab-pglake-data:/home/postgres/pgsql-17/data \
  -e PG_MAJOR=17 --entrypoint /entrypoint-postgres.sh $IMG_PGLAKE >/dev/null
wait_pg lab-pglake
