#!/usr/bin/env bash
# Load exported runtime fields first. This child receives no setup credentials.
set -euo pipefail
exec env -i PATH="$PATH" \
  PGHOST="${PGHOST:?}" PGPORT="${PGPORT:?}" PGDATABASE="${PGDATABASE:?}" \
  PGUSER="${PGUSER:?}" PGPASSWORD="${PGPASSWORD:?}" PGSSLROOTCERT="${PGSSLROOTCERT:?}" \
  CLICKHOUSE_URL="${CLICKHOUSE_URL:?}" CLICKHOUSE_USER="${CLICKHOUSE_USER:?}" \
  CLICKHOUSE_PASSWORD="${CLICKHOUSE_PASSWORD:?}" ACCOUNT_TOKENS="${ACCOUNT_TOKENS:?}" \
  PORT="${PORT:-3000}" node dist/src/main.js
