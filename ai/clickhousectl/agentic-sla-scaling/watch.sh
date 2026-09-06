#!/usr/bin/env bash
# Read-only after the Query API has been enabled during setup.
set -euo pipefail
# shellcheck source=common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
if (( $# > 1 )) || [[ "${1:-}" != '' && "${1:-}" != --once ]]; then
  echo "usage: $0 [--once]" >&2
  exit 1
fi
sla_config
while true; do
  status=0
  if sla_snapshot; then
    print_snapshot
  else
    echo "[$(date +%T)] UNKNOWN (SLA snapshot unavailable)" >&2
    status=1
  fi
  if metrics=$(clickhousectl cloud service prometheus "$SERVICE_ID" --filtered-metrics true); then
    # Keep per-replica labels. Counters need deltas over time, not a one-sample
    # interpretation as CPU utilization. Missing metrics are not zero pressure.
    selected=$(printf '%s\n' "$metrics" | awk '
      /^(ClickHouseMetrics_(Query|BackgroundMergesAndMutationsPoolTask)|ClickHouseAsyncMetrics_CGroup[^ {]*|ClickHouseProfileEvents_(UserTimeMicroseconds|SystemTimeMicroseconds|OSCPUWaitMicroseconds))[ {]/ {print "    " $0}')
    if [[ -n "$selected" ]]; then
      printf '%s\n' "$selected"
    else
      echo '    No matching pressure metrics returned.' >&2
    fi
  else
    echo '    Prometheus metrics unavailable; pressure is unknown.' >&2
    status=1
  fi
  [[ "${1:-}" != --once ]] || exit "$status"
  sleep 10
done
