#!/usr/bin/env bash
# Hand the breach to the agent. Run this once watch.sh shows a breach.
# Install skills first (one-time):  clickhousectl skills --agent claude
#
# Prompt is piped via stdin (claude's --allowedTools is variadic/greedy and
# would otherwise swallow a positional prompt). We scope the agent to
# clickhousectl only.
#
set -euo pipefail
: "${SERVICE_ID:?source config.env first}"
SLA_MS="${SLA_MS:-200}"

p99=$(clickhousectl cloud service query --id "$SERVICE_ID" --format TSV --query "
  SELECT round(quantile(0.99)(query_duration_ms))
  FROM clusterAllReplicas(default, system.query_log)
  WHERE event_time > now() - INTERVAL 1 MINUTE
    AND type='QueryFinish' AND log_comment='frontend-dashboard'")

read -r -d '' PROMPT <<EOF || true
The 'frontend-dashboard' query latency SLA on ClickHouse Cloud service $SERVICE_ID
has just breached: p99 over the last minute is ${p99}ms against a ${SLA_MS}ms target.

You're the on-call agent. Work out WHY the SLA is breaching, then remediate it by
applying exactly one scaling action to the service. Let the evidence drive the choice.

What you have to work with (clickhousectl only):
  - SQL against the service's system tables:
      clickhousectl cloud service query --id $SERVICE_ID --format TSV --query "<SQL>"
    system.query_log is the richest source — one row per executed query, with its
    timing and memory use, and each query tagged with the workload it belongs to in
    the log_comment column ('frontend-dashboard' is the SLA workload). Filter to
    type='QueryFinish' for completed queries; use clusterAllReplicas to see all
    replicas.
  - Live resource pressure from Prometheus (CPU, memory against the per-replica
    limit, query concurrency, background merges):
      clickhousectl cloud service prometheus $SERVICE_ID --filtered-metrics true

Your two scaling levers — apply only ONE, whichever the root cause calls for:
  - Change the replica count:
      clickhousectl cloud service scale $SERVICE_ID --num-replicas N
  - Change the size (memory) of each replica:
      clickhousectl cloud service scale $SERVICE_ID --min-replica-memory-gb M --max-replica-memory-gb M

General advice on which scaling pattern to use:
- Prefer scaling vertically if cause is unclear.
- Scale vertically if latency is likely caused by resource contention from other queries.
- Scale horizontally if latency is caused by an increase in query concurrency or write throughput.

Apply one action, then explain the evidence you relied on and why that lever fits.
EOF

printf '%s' "$PROMPT" | claude -p --model sonnet --allowedTools "Bash(clickhousectl:*)"
