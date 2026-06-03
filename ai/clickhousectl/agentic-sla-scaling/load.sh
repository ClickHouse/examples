#!/usr/bin/env bash
# Pressure generator via native `clickhouse benchmark`.
#
#   ./load.sh horizontal [concurrency]
#       The SAME dashboard query, but from many more users (high QPS of the
#       light query). Inflates the monitored 'frontend-dashboard' rate; memory
#       stays low. Correct fix: HORIZONTAL (more replicas to serve the volume).
#
#   ./load.sh vertical [concurrency]
#       A DIFFERENT, heavy analytics workload ('analytics-batch') that pins
#       CPU/memory at low concurrency while the dashboard rate stays at its
#       baseline. Correct fix: VERTICAL (a bigger replica).
#
# Run the steady baseline (frontend.sh) alongside BOTH so there is always a
# normal stream of dashboard queries whose p99 is the SLA.
set -euo pipefail
: "${CH_HOST:?source config.env first}" "${CH_PASSWORD:?}"

MODE="${1:-vertical}"; C="${2:-}"
case "$MODE" in
  horizontal)
     C="${C:-256}"
     # The SAME dashboard query as frontend.sh — just lots more of it, fired
     # back-to-back. Each query is individually cheap (a few ms; it scans a
     # 1-day window via the index), so it takes a lot of them in flight to
     # saturate the ~2-core replica's query-thread pool. Once the queue gets
     # deep enough the dashboard p99 climbs past the SLA. The cost is compute,
     # not disk I/O, so this breaches the same whether the page cache is cold
     # or warm. The signal in query_log is a high RATE of the (cheap,
     # low-memory) dashboard query -> add replicas.
     # Keep this byte-identical to the query in frontend.sh.
     Q="SELECT event_type,count(),avg(value),quantile(0.9)(value) FROM events
        WHERE event_type='purchase' AND event_time>now()-INTERVAL 1 DAY
        GROUP BY event_type SETTINGS log_comment='frontend-dashboard'"
     EXTRA="-d 0";;        # delay 0: fire as fast as possible
  vertical)
     C="${C:-4}"
     # Separate heavy analytics job: full-scan + per-row trig, grouped by user.
     # CPU- and memory-hungry, but bounded (won't OOM the 8 GiB box). Even a
     # handful in flight pin CPU on the ~2-core replica and starve every other
     # query of cycles, so the dashboard query's steady compute cost balloons
     # well past the SLA -- while the dashboard's OWN arrival rate stays at
     # baseline. The signal in query_log is a single heavy query type burning
     # CPU/memory at low QPS -> the fix is a bigger box.
     Q="SELECT user_id, count(), avg(sin(value) + cos(value)) FROM events
        GROUP BY user_id ORDER BY 2 DESC LIMIT 20
        SETTINGS log_comment='analytics-batch'"
     EXTRA="";;
  *) echo "usage: $0 horizontal|vertical [concurrency]" >&2; exit 1;;
esac

echo "scenario $MODE, concurrency=$C (ctrl-c to stop)"
clickhouse benchmark \
  --host "$CH_HOST" --port "${CH_PORT:-9440}" --secure \
  --user "${CH_USER:-default}" --password "$CH_PASSWORD" \
  -c "$C" $EXTRA \
  --query "$Q"
