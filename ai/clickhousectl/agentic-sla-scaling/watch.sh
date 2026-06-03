#!/usr/bin/env bash
# Read-only watcher. Prints the SLA p99 and the key
# resource-pressure metrics side by side so you can see the breach and
# eyeball the root cause before handing off to the agent.
set -euo pipefail
: "${SERVICE_ID:?source config.env first}"
SLA_MS="${SLA_MS:-200}"

SLA="SELECT toUInt64(quantile(0.99)(query_duration_ms))
     FROM clusterAllReplicas(default, system.query_log)
     WHERE event_time > now() - INTERVAL 1 MINUTE
       AND type='QueryFinish' AND log_comment='frontend-dashboard'"

while true; do
  p99=$(clickhousectl cloud service query --id "$SERVICE_ID" --format TSV --query "$SLA" 2>/dev/null || echo "?")
  flag=""; [[ "$p99" =~ ^[0-9]+$ ]] && (( p99 > SLA_MS )) && flag="  <-- BREACH"
  echo "[$(date +%T)] p99=${p99}ms (SLA ${SLA_MS}ms)${flag}"
  # Prometheus exposition format is `Name{labels} value` (labels optional), so
  # match the metric name followed by either '{' or a space. Guard with
  # `|| true` so a no-match grep (exit 1) doesn't trip `set -o pipefail` and
  # kill the loop.
  clickhousectl cloud service prometheus "$SERVICE_ID" --filtered-metrics true 2>/dev/null \
    | grep -E '^(ClickHouseMetrics_Query|ClickHouseAsyncMetrics_CGroupMemoryUsed|ClickHouseMetrics_BackgroundMergesAndMutationsPoolTask)[ {]' \
    | sed 's/^/    /' || true
  sleep 10
done
