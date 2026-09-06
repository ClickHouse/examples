# Agentic SLA-breach detection and scaling

Generate pressure on a dedicated ClickHouse Cloud service, watch a dashboard query exceed its server-side latency target, and hand the breach to an AI agent. The agent uses [`clickhousectl`](https://github.com/ClickHouse/clickhousectl) to inspect query logs, metrics and service settings. It can request **at most one scale-up action, or make no change** when scaling is not justified.

This is a Cloud scaling demonstration, not a production autoscaler or a guarantee that adding capacity fixes an incident. The workload names describe intended pressure patterns; either scenario can have more than one suitable remedy.

## Cloud scope and prerequisites

[Try ClickHouse Cloud](https://clickhouse.com/cloud) with $300 in credits for a 30-day trial. Use a **dedicated disposable service** in a Scale or Enterprise organization with a standard profile that supports both manual horizontal and vertical scaling. Basic services have fixed size; Enterprise custom profiles can require support for vertical resizing. See the [scaling documentation](https://clickhouse.com/docs/manage/scaling).

A local server can run the SQL smoke checks, but it cannot exercise Cloud service scaling, the Cloud Query API or Cloud Prometheus. For a local AI application walkthrough, use the [MCP examples](../../mcp/README.md).

You need Bash, `awk`, `xargs`, and:

1. **clickhousectl** (checked with 0.4.2):

   ```bash
   curl -fsSL https://clickhouse.com/cli | sh
   export PATH="$HOME/.local/bin:$PATH"
   clickhousectl --version
   ```

2. **Cloud API authentication**, separate from the database username/password. Log in in your own terminal using a Cloud API key and secret. An Admin API key is needed to provision the per-service Query API key on first use; read-only OAuth cannot perform scaling. Use credentials for the organization containing the demo service.

   ```bash
   clickhousectl cloud auth login --api-key <key-id> --api-secret <key-secret>
   clickhousectl cloud auth status
   clickhousectl cloud org list
   ```

3. **The native ClickHouse client and benchmark**, pinned to the verified stable build. `latest` selects a rolling master build, so this example uses an exact version:

   ```bash
   clickhousectl local use 26.8.2.7
   clickhouse client --version
   ```

4. **[Claude Code](https://code.claude.com/docs/en/overview)** (CLI flags checked with 2.1.263), installed and authenticated in the environment where you run the example. The script defaults to its `sonnet` alias; set `CLAUDE_MODEL` to use another model available to your account. The agent receives CLI guidance in its prompt. Optionally install additional ClickHouse skills from the example directory:

   ```bash
   clickhousectl skills --agent claude
   ```

## Files

| File | Role |
|------|------|
| `schema.sql` | Creates `sla_demo.events` and seeds a configurable fixture (200M rows for the load demonstration). A repeat run leaves a nonempty table unchanged. |
| `dashboard.sql` | Dashboard query shared by the frontend and horizontal load, tagged `frontend-dashboard`. |
| `analytics.sql` | Full-scan analytics query tagged `analytics-batch`. |
| `frontend.sh` | Four dashboard requests per batch, with a one-second pause between batches. Stops and reports client/query errors. |
| `load.sh` | Native `clickhouse benchmark` pressure: more dashboard requests (`horizontal`) or a heavy grouped analytics query (`vertical`). |
| `sla.sql`, `common.sh` | Shared one-minute latency snapshot and validation. |
| `watch.sh` | Reports the snapshot and per-replica pressure metrics every 10 seconds; `--once` takes one sample. |
| `investigate.sh` | Rechecks the breach, then runs Claude Code to investigate and optionally request one scale-up. |

## Create or select the demo service

Run all commands from `ai/clickhousectl/agentic-sla-scaling`.

```bash
# Replace the CIDR with the public egress IP of the machine running this demo.
# The fixed memory range makes the agent's manual action observable.
clickhousectl cloud service create --name sla-demo \
  --provider aws --region eu-west-1 \
  --ip-allow <your-public-ip>/32 \
  --min-replica-memory-gb 8 --max-replica-memory-gb 8 \
  --num-replicas 1 --idle-scaling false

cp config.env.example config.env
chmod 600 config.env
# Edit config.env: save the service ID, native TLS host/port and initial password.
# The initial database password is printed once. Do not put API keys in this file.
source config.env

# Repeat until state is running. Creation returns before the service is ready.
clickhousectl cloud service get "$SERVICE_ID"

# Enable/verify the Query API once. watch/investigate subsequently use
# --no-auto-enable so diagnostics do not silently provision a new API key.
clickhousectl cloud service query --id "$SERVICE_ID" --query 'SELECT version()'

# Verify the native TLS endpoint independently of the Query API.
export CLICKHOUSE_PASSWORD="$CH_PASSWORD"
clickhouse client --host "$CH_HOST" --port "$CH_PORT" --secure \
  --user "$CH_USER" --query 'SELECT version()'
```

You can use an existing **disposable** service instead of creating one. Record its initial replica count and memory settings, verify its tier/profile and IP access, and fill in `config.env`. Use fixed memory (min = max) with vertical autoscaling mode for this walkthrough. The agent is instructed to make no change for a variable memory range, horizontal autoscaling mode, or an in-progress scaling operation. The replica-count command is manual horizontal scaling; it does not enable the separate horizontal autoscaling feature.

If the database password was lost, `clickhousectl cloud service reset-password "$SERVICE_ID"` issues a new one; it changes credentials for that service. If a stored Query API key is rejected, resolve that explicitly with `clickhousectl cloud service repair-query-key "$SERVICE_ID"` and rerun the query check.

## Smoke check, then load the fixture

First verify the schema and both queries with 100,000 rows. Use the native client for the multi-statement file and long insert: the Cloud Query API accepts one statement and has an approximately 30-second request timeout.

```bash
clickhouse client --host "$CH_HOST" --port "$CH_PORT" --secure \
  --user "$CH_USER" --multiquery --param_rows=100000 --queries-file schema.sql
clickhouse client --host "$CH_HOST" --port "$CH_PORT" --secure \
  --user "$CH_USER" --queries-file dashboard.sql
clickhouse client --host "$CH_HOST" --port "$CH_PORT" --secure \
  --user "$CH_USER" --queries-file analytics.sql

# Replace only this disposable fixture before the full load. No workloads yet.
clickhouse client --host "$CH_HOST" --port "$CH_PORT" --secure \
  --user "$CH_USER" --query 'TRUNCATE TABLE sla_demo.events'
clickhouse client --host "$CH_HOST" --port "$CH_PORT" --secure \
  --user "$CH_USER" --multiquery --param_rows="$DEMO_ROWS" --queries-file schema.sql
clickhouse client --host "$CH_HOST" --port "$CH_PORT" --secure \
  --user "$CH_USER" --query 'SELECT count() FROM sla_demo.events'
```

Expect `DEMO_ROWS` rows; loading time and resource use depend on the service. Re-running the seed leaves a nonempty table unchanged, including after a partial insert. If a load was interrupted, stop the workloads, truncate this demo table and reload. Refresh the fixture before a later session because the dashboard selects the last day relative to `now()`.

## Reproduce a breach and investigate

Open three terminals in this directory and run `source config.env` in each:

```bash
# Terminal 1: establish a baseline below the target before adding pressure.
bash frontend.sh

# Terminal 2: wait for at least MIN_SAMPLES completions in the one-minute window.
bash watch.sh

# Terminal 3: run ONE pressure scenario.
bash load.sh vertical         # default concurrency: 4
# Or, after stopping the previous load:
bash load.sh horizontal       # default concurrency: 256
```

When the watcher prints `BREACH`, run this in another configured terminal:

```bash
bash investigate.sh
```

The script will not start Claude if the snapshot fails, has fewer than `MIN_SAMPLES` successes (default 100), or no longer exceeds `SLA_MS`. On a current breach, it pre-approves service inspection, SQL queries, metrics and scaling commands for the selected service. **Running it can increase Cloud costs.** Its prompt asks the agent to stay within 3 replicas or 32 GiB per replica, make at most one change, and abstain when the evidence does not support scaling. These are agent instructions, not enforced infrastructure limits.

The script limits built-in tools to Bash and disables inherited MCP servers. The [Claude Code permission flags](https://code.claude.com/docs/en/cli-reference) are not a security sandbox; inherited permissions and the Cloud API credential's privileges still matter. Keep this workflow in a dedicated demo environment.

Leave the frontend and watcher running to observe the result. A successful scale API response means the request was accepted; wait for the new capacity and a fresh post-change sample window before judging recovery. Do not keep rerunning the agent while a scale operation is in progress.

```bash
clickhousectl cloud service get "$SERVICE_ID" --json
clickhousectl cloud activity list
```

## Interpreting the measurement and tuning pressure

The watcher uses **exact p99 of successful initial dashboard queries completed in the last 60 seconds**, aggregated across replicas. It excludes internal distributed subqueries. Failed requests are counted separately; an `OK` latency sample with failures is not a healthy workload. In-flight requests and client/network time are absent from this measure, and asynchronous query-log flushing delays visibility. This is a query-latency target, not a complete user-facing availability SLA. See [`system.query_log`](https://clickhouse.com/docs/operations/system-tables/query_log).

`NO_DATA`, `INSUFFICIENT_SAMPLES` and `UNKNOWN` are distinct from `OK`. One-shot mode exits nonzero on a Query API or metrics error. Prometheus output preserves replica labels; counters require differences over time, and missing metrics do not mean zero pressure.

The original demonstration used fixed 8 GiB replicas and `SLA_MS=200`. The 200M-row breach and recovery scenarios have **not been revalidated** in this refresh. Establish a baseline on your service, then adjust concurrency (`bash load.sh horizontal 384` or `bash load.sh vertical 8`) or the time window in `dashboard.sql`. Both dashboard producers read that same file. The analytics workload can exhaust resources; reduce concurrency if query errors dominate. Query result caching is disabled for both workloads, but other caches and service conditions can still affect latency.

## Cleanup

Stop `load.sh`, `frontend.sh` and `watch.sh` with Ctrl-C before stopping or deleting the service; continued requests can prevent idling or wake an idle service.

To keep the service and data for later:

```bash
clickhousectl cloud service stop "$SERVICE_ID"
```

Stopping preserves data and can retain storage/backup charges. It is not teardown. To permanently remove the **disposable service created for this demo**, verify its ID and then delete it:

```bash
clickhousectl cloud service get "$SERVICE_ID"
clickhousectl cloud service delete "$SERVICE_ID" --force
```

Deletion is irreversible; `--force` stops a running service before deleting it. Do not delete a shared service. Remove the local `config.env` when finished.
