#!/usr/bin/env bash
# These workloads illustrate different pressures; the appropriate response
# depends on observed resource use, service configuration and latency.
set -euo pipefail
# shellcheck source=common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
if (( $# > 2 )); then
  echo "usage: $0 horizontal|vertical [concurrency]" >&2
  exit 1
fi
MODE=${1:-vertical}
case "$MODE" in
  horizontal)
    C=${2:-256}
    Q=$(<"$SCRIPT_DIR/dashboard.sql")
    ;;
  vertical)
    C=${2:-4}
    Q=$(<"$SCRIPT_DIR/analytics.sql")
    ;;
  *) echo "usage: $0 horizontal|vertical [concurrency]" >&2; exit 1 ;;
esac
positive_integer concurrency "$C"
native_connection

echo "scenario $MODE, concurrency=$C (ctrl-c to stop)"
exec clickhouse benchmark "${NATIVE_ARGS[@]}" --concurrency "$C" --query "$Q"
