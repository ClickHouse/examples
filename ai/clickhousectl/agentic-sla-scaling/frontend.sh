#!/usr/bin/env bash
# Steady "frontend" traffic: ~4 light, selective queries in flight, tagged
# log_comment='frontend-dashboard'. This is the SLA we defend.
# query_duration_ms in query_log is server-side only, so CLI startup cost
# does not pollute the measured latency.
set -euo pipefail
: "${CH_HOST:?source config.env first}" "${CH_PASSWORD:?}"

Q="SELECT event_type,count(),avg(value) FROM events
   WHERE event_type='purchase' AND event_time>now()-INTERVAL 1 HOUR
   GROUP BY event_type SETTINGS log_comment='frontend-dashboard'"

echo "frontend traffic -> ${CH_HOST} (ctrl-c to stop)"
while true; do
  seq 4 | xargs -P4 -I{} clickhouse client \
    --host "$CH_HOST" --port "${CH_PORT:-9440}" --secure \
    --user "${CH_USER:-default}" --password "$CH_PASSWORD" \
    --format Null --query "$Q" || true
  sleep 1
done
