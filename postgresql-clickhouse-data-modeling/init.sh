#!/bin/sh
set -eu
cd "$(dirname "$0")"
case "${1:-}" in
  ""|--existing-data) ;;
  *) echo "Usage: $0 [--existing-data]" >&2; exit 1 ;;
esac
ready=false
attempt=0
while [ "$attempt" -lt 30 ]; do
  attempt=$((attempt + 1))
  if docker compose exec -T postgres pg_isready -h 127.0.0.1 -U admin -d clickhouse_pg_db >/dev/null 2>&1 &&
     docker compose exec -T clickhouse clickhouse-client --user demo --password local-example-password \
       --connect_timeout 3 --receive_timeout 10 --query 'SELECT 1' >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 2
done
[ "$ready" = true ] || { echo 'Postgres/ClickHouse readiness timed out' >&2; exit 1; }
if [ "${1:-}" != --existing-data ]; then
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U admin -d clickhouse_pg_db < fixtures/seed.sql
fi
docker compose exec -T clickhouse clickhouse-client --user demo --password local-example-password \
  --connect_timeout 3 --receive_timeout 10 --query 'CREATE DATABASE IF NOT EXISTS stackoverflow'
docker compose run --rm --no-deps bootstrap
if [ "${1:-}" = --existing-data ]; then
  echo 'Mirror created for existing data; query logical state with FINAL and deletion filtering'
else
  echo 'Mirror created; run ./verify.sh initial for the tiny fixture'
fi
