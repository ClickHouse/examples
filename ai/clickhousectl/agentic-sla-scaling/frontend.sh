#!/usr/bin/env bash
# Four dashboard requests per batch, then a one-second pause. The SQL and tag
# are shared with load.sh horizontal. Client startup is not part of query_log latency.
set -euo pipefail
# shellcheck source=common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
native_connection
Q=$(<"$SCRIPT_DIR/dashboard.sql")

echo "frontend traffic -> ${CH_HOST} (ctrl-c to stop)"
while true; do
  # Surface connection/SQL failures and stop instead of silently retrying forever.
  seq 4 | xargs -P4 -I{} clickhouse client "${NATIVE_ARGS[@]}" --format Null --query "$Q"
  sleep 1
done
