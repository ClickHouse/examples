#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${PGUSER:-}" != checklist_owner ]]; then
  printf '%s\n' 'Migrations must use checklist_owner.' >&2
  exit 1
fi
if [[ "${PGSSLMODE:-}" != verify-full || -z "${PGSSLROOTCERT:-}" ]]; then
  printf '%s\n' 'Set PGSSLMODE=verify-full and the official PGSSLROOTCERT.' >&2
  exit 1
fi
direction="${1:-up}"
case "$direction" in
  up)
    checksum=$(sha256sum sql/migrations/001-up.sql | cut -d ' ' -f 1)
    psql -X -v ON_ERROR_STOP=1 -v checksum="$checksum" <<'SQL'
BEGIN;
SELECT pg_advisory_xact_lock(5870031002);
CREATE TABLE IF NOT EXISTS checklist_storage.schema_migrations (
    version integer PRIMARY KEY, checksum text NOT NULL
);
SELECT NOT EXISTS (SELECT FROM checklist_storage.schema_migrations WHERE version = 1) AS needed \gset
\if :needed
\i sql/migrations/001-up.sql
INSERT INTO checklist_storage.schema_migrations VALUES (1, :'checksum');
\else
SELECT checksum = :'checksum' AS agrees FROM checklist_storage.schema_migrations WHERE version = 1 \gset
\if :agrees
\echo Migration 1 already applied with matching checksum.
\else
\echo Migration checksum changed; refusing to continue.
\quit 1
\endif
\endif
COMMIT;
SQL
    ;;
  down)
    psql -X -v ON_ERROR_STOP=1 <<'SQL'
BEGIN;
SELECT pg_advisory_xact_lock(5870031002);
\i sql/migrations/001-down.sql
COMMIT;
SQL
    ;;
  *) printf '%s\n' 'Usage: scripts/migrate.sh up|down' >&2; exit 1 ;;
esac
