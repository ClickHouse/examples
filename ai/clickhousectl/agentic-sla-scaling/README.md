# Agentic SLA-breach detection and scaling

A demo of an agent that keeps a latency SLA: a defended query-latency target on a ClickHouse Cloud service, a way to manufacture realistic pressure against it, and an AI agent that investigates a breach and applies the right scaling action — horizontal or vertical — on its own.

You generate load, watch the SLA breach, then hand the breach to the agent. The agent inspects the live system (`system.query_log`, Prometheus metrics) via [`clickhousectl`](https://github.com/ClickHouse/clickhousectl) and reasons its way to the correct lever.

## How it works

| File | Role |
|------|------|
| `schema.sql` | A ~200M-row `events` table (CREATE & INSERT statements)|
| `frontend.sh` | Simulates "frontend" traffic, sends ~4 dashboard queries in flight, tagged `log_comment='frontend-dashboard'`. This is the SLA we defend. |
| `load.sh` | Pressure generator using `clickhouse benchmark`. `horizontal` fires lots more of the same dashboard query. `vertical` runs a different, heavy analytics query that pins CPU/memory. |
| `watch.sh` | Read-only watcher: prints the SLA p99 alongside the key resource-pressure metrics every 10s so you can see the breach and eyeball the cause. |
| `investigate.sh` | Hands the breach to the agent (`claude -p`, scoped to `clickhousectl` only). The prompt states the breach and the available data sources. |

## Prereqs

- [`clickhousectl`](https://github.com/ClickHouse/clickhousectl) installed:
  ```
  curl https://clickhouse.com/cli | sh
  ```
- `clickhousectl` authenticated against ClickHouse Cloud:
  ```
  clickhousectl cloud auth login --api-key ... --api-secret ...
  ```
- The `clickhouse` binary on your PATH. Install the latest and put it on the path with:
  ```
  clickhousectl local use latest
  ```
  This provides `clickhouse client` (used by `frontend.sh`) and `clickhouse benchmark` (used by `load.sh`).
- [Claude Code](https://docs.claude.com/en/docs/claude-code/overview), plus the ClickHouse agent skills:
  ```
  clickhousectl skills --agent claude
  ```

## Run it

Run through these steps (or, just ask Claude to do it for you):

```bash
# 1. Create the service
clickhousectl cloud service create --name sla-demo \
  --provider aws --region eu-west-1 \
  --min-replica-memory-gb 8 --max-replica-memory-gb 8 \
  --num-replicas 1 --idle-scaling false

# 2. Fill in connection details using the output of the first command (service id, host, port, default-user pass)
cp config.env.example config.env
vim config.env # enter the details here
source config.env

# 3. Load data (~200M rows, ~100s). Use the native client, not the HTTP query
#    API: the query API rejects multi-statement files and times out on the
#    big INSERT.
clickhouse client --host "$CH_HOST" --port "${CH_PORT:-9440}" --secure \
  --user "${CH_USER:-default}" --password "$CH_PASSWORD" \
  --queries-file schema.sql

# 4. Three terminals (all: source config.env first)
bash frontend.sh             # steady frontend traffic (the SLA)
bash watch.sh                # SLA p99 + resource pressure, every 10s
bash load.sh vertical        # scenario: resource contention -> expect VERTICAL
#   ...or...
bash load.sh horizontal      # scenario: query concurrency  -> expect HORIZONTAL

# 5. When watch.sh prints "<-- BREACH", hand off to the agent
bash investigate.sh

# 6. Confirm + tear down
clickhousectl cloud activity list   # the agent's scale action is in the audit log
clickhousectl cloud service get "$SERVICE_ID" # view the service details to see the scale
clickhousectl cloud service stop "$SERVICE_ID"   # tear it down
```

## Tuning the breach

The defaults are sized for the demo service above (8 GiB / ~2 vCPU, `SLA_MS=200`).
The breach is driven by the dashboard query's fixed compute cost, which is
cache-independent, so it should fire reliably — but if you change the service
size, the SLA, or the data volume, you have two knobs:

- **Concurrency** — pass it as the second arg: `bash load.sh vertical 8` or
  `bash load.sh horizontal 384`. More concurrency = a deeper run queue = a
  harder breach. The `horizontal` default (256) is tuned for the 8 GiB / ~2
  vCPU service above; the dashboard query is individually cheap, so it takes a
  few hundred in flight to saturate the query-thread pool. Watch `watch.sh`; if
  p99 is climbing but not crossing the SLA, bump it.
- **Per-query cost** — the `INTERVAL 1 DAY` window in the dashboard query
  (`frontend.sh` _and_ the `horizontal` branch of `load.sh` — keep the two
  byte-identical). A wider window scans and aggregates more rows, raising the
  baseline cost so the breach lands at lower concurrency. The baseline (4 in
  flight) should still sit comfortably under `SLA_MS`.
