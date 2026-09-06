#!/bin/sh
set -eu
cd "$(dirname "$0")"
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 \
  -U admin -d clickhouse_pg_db < fixtures/changes.sql
