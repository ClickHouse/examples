#!/usr/bin/env bash
set -euo pipefail
# Load a runtime-only app.env in a fresh shell before calling this script.
exec env -i PATH="$PATH" HOME="$HOME" \
  PGHOST="$PGHOST" PGPORT="$PGPORT" PGDATABASE="$PGDATABASE" \
  PGUSER="$PGUSER" PGPASSWORD="$PGPASSWORD" PGSSLROOTCERT="$PGSSLROOTCERT" \
  USER_TOKENS="$USER_TOKENS" PORT="${PORT:-3000}" \
  .build/debug/Invitations serve --env production
