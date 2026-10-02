#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${PGSSLROOTCERT:?Cloud CA required}"
test "${PGUSER:?Schema owner required}" = playlist_owner
export PGSSLMODE=verify-full
case "${1:-up}" in
 up) export MIGRATION_SHA; MIGRATION_SHA=$(sha256sum migrations/001-up.sql | cut -d ' ' -f1); psql -X -v ON_ERROR_STOP=1 -f migrations/001-up.sql ;;
 down) psql -X -v ON_ERROR_STOP=1 -f migrations/001-down.sql ;;
 *) echo 'Use up or down' >&2; exit 2 ;;
esac
