#!/usr/bin/env bash
# Steady "frontend" traffic: ~4 dashboard queries in flight, tagged
# log_comment='frontend-dashboard'. This is the SLA we defend.
# query_duration_ms in query_log is server-side only, so CLI startup cost
# does not pollute the measured latency.
#
# The query is selective (event_type uses the index) but scans a multi-day
# window and aggregates it, so each run costs a steady ~tens of ms of CPU
# that does NOT depend on the page cache being warm. That fixed compute cost
# is what makes the breaches reliable: under CPU contention it stretches well
# past the SLA, and a moderate number of concurrent copies saturate the box.
# Baseline (4 in flight) sits well under SLA_MS; the load scripts push it over.
#
# IMPORTANT: keep this query byte-identical to the 'horizontal' query in
# load.sh — the horizontal scenario is "the same dashboard query, just lots
# more of it".
set -euo pipefail
: "${CH_HOST:?source config.env first}" "${CH_PASSWORD:?}"

Q="SELECT event_type,count(),avg(value),quantile(0.9)(value) FROM events
   WHERE event_type='purchase' AND event_time>now()-INTERVAL 1 DAY
   GROUP BY event_type SETTINGS log_comment='frontend-dashboard'"

echo "frontend traffic -> ${CH_HOST} (ctrl-c to stop)"
while true; do
  seq 4 | xargs -P4 -I{} clickhouse client \
    --host "$CH_HOST" --port "${CH_PORT:-9440}" --secure \
    --user "${CH_USER:-default}" --password "$CH_PASSWORD" \
    --format Null --query "$Q" || true
  sleep 1
done
