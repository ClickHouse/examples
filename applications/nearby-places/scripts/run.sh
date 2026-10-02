#!/usr/bin/env bash
set -euo pipefail
: "${PGHOST:?}" "${PGPORT:=5432}" "${PGSSLROOTCERT:?}"
: "${PORT:=4000}"
# PG* is required by Postgres.js's configuration defaults. No write/run/FFI grants.
exec deno run --frozen --cached-only \
  --allow-net="127.0.0.1:$PORT,$PGHOST:$PGPORT" \
  --allow-read="public,$PGSSLROOTCERT" \
  --allow-env='PG*,PORT,NODE_DEBUG,NODE_EXTRA_CA_CERTS' \
  src/server.ts
