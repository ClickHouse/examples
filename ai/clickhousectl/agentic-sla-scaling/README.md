# Agentic SLA-breach detection and scaling

A self-contained demo of an **agent that keeps a latency SLA**: a defended
query-latency target on a ClickHouse Cloud service, a way to manufacture
realistic pressure against it, and an AI agent that investigates a breach and
applies the *right* scaling action — horizontal or vertical — on its own.

There's no cron and no hard-coded answer. You generate load, watch the SLA
breach, then hand the breach to the agent. The agent inspects the live system
(`system.query_log`, Prometheus metrics) via [`clickhousectl`](https://github.com/ClickHouse/clickhousectl)
and reasons its way to the correct lever.

## How it works

| File | Role |
|------|------|
| `schema.sql` | A ~200M-row `events` table. `ORDER BY (event_type, event_time)` is the lever: the dashboard query filters on `event_type` (hits the index → fast), while the heavy analytics query groups across all `user_id` (full scan → heavy). |
| `frontend.sh` | Steady "frontend" traffic — ~4 light dashboard queries in flight, tagged `log_comment='frontend-dashboard'`. This is the SLA we defend. Runs over the native protocol via `clickhouse client`. |
| `load.sh` | Pressure generator via native `clickhouse benchmark`. `horizontal` fires lots more of the *same* light query (concurrency pressure → scale out). `vertical` runs a *different*, heavy analytics query that pins CPU/memory (resource contention → scale up). |
| `watch.sh` | Read-only watcher: prints the SLA p99 alongside the key resource-pressure metrics every 10s so you can see the breach and eyeball the cause. |
| `investigate.sh` | Hands the breach to the agent (`claude -p`, scoped to `clickhousectl` only). The prompt states the breach and the available data sources and scaling levers, but **not** which scenario it's in — the agent has to work it out. |

## Prereqs

- [`clickhousectl`](https://github.com/ClickHouse/clickhousectl), authenticated against ClickHouse Cloud:
  ```
  clickhousectl cloud auth login --api-key ... --api-secret ...
  ```
- The `clickhouse` binary on your PATH. Install the latest and put it on the
  path with:
  ```
  clickhousectl local use latest
  ```
  This provides `clickhouse client` (used by `frontend.sh`) and
  `clickhouse benchmark` (used by `load.sh`). Both run over the native protocol
  rather than HTTP, which gets rate-limited under sustained fan-out.
- The [`claude` CLI](https://docs.claude.com/en/docs/claude-code/overview), plus the ClickHouse agent skills:
  ```
  clickhousectl skills --agent claude
  ```

## Run it

```bash
# 1. Create the service (this costs money until you stop/delete it)
clickhousectl cloud service create --name sla-demo \
  --provider aws --region us-east-1 \
  --min-replica-memory-gb 8 --max-replica-memory-gb 8 \
  --num-replicas 1 --idle-scaling false

# 2. Fill in connection details
clickhousectl cloud service list                          # grab the SERVICE_ID
clickhousectl cloud service get "$SERVICE_ID"             # native host/port
clickhousectl cloud service reset-password "$SERVICE_ID"  # default-user password
cp config.env.example config.env && $EDITOR config.env
source config.env

# 3. Load data (~200M rows)
clickhousectl cloud service query --id "$SERVICE_ID" --queries-file schema.sql

# 4. Three terminals (all: source config.env first)
bash frontend.sh             # steady frontend traffic (the SLA)
bash watch.sh                # SLA p99 + resource pressure, every 10s
bash load.sh vertical 3      # scenario: resource contention -> expect VERTICAL
#   ...or...
bash load.sh horizontal 40   # scenario: query concurrency  -> expect HORIZONTAL

# 5. When watch.sh prints "<-- BREACH", hand off to the agent
bash investigate.sh

# 6. Confirm + tear down
clickhousectl cloud activity list   # the agent's scale action is in the audit log
clickhousectl cloud service scale "$SERVICE_ID" \
  --num-replicas 1 --min-replica-memory-gb 8 --max-replica-memory-gb 8
clickhousectl cloud service stop "$SERVICE_ID"   # or delete
```

## Tuning notes

- 8GB ≈ 2 vCPU, so the `vertical` scenario breaches fast. Ramp its concurrency
  up until `CGroupMemoryUsed` pins near the limit but queries don't OOM — an
  OOM'd query errors instead of slowing the frontend, which muddies the SLA.
- The `horizontal` scenario keeps memory low; raise concurrency until queries
  queue and the frontend p99 climbs from *waiting*, not from *work*.
- Re-run a scenario after the agent scales to confirm the SLA recovers.
