# Building report results and run history with ClickHouse Cloud

Editorial status: proposed engineering resource, not a published page. Review
the companion example before publication. While the code PR is under review,
link to its PR branch; update the link to `main` only after merge.

This walkthrough builds a small command-line sales-reporting application. It
reads sales CSV files, writes human-readable Markdown reports, and stores the
result rows and completed-run history in ClickHouse. You can find an earlier
run or compare revenue across reports without reopening each input file.

The design question is: **can an application keep analytical results and the
metadata needed to find completed reports in one ClickHouse service?** For
this append-oriented workflow, the example shows how to do that, including
retries and incomplete writes. A run-history table does not, by itself, require
a separate transactional database.

ClickHouse Cloud is the platform for both ClickHouse and ClickHouse Managed
Postgres services. This example provisions only the ClickHouse analytical
service; the transactional alternative discussed below is also part of
ClickHouse Cloud.

The [runnable TypeScript example](https://github.com/ClickHouse/examples/tree/add-report-history-example/applications/report-history)
implements that lifecycle, including interruption tests. It uses the official
JavaScript client and provisions infrastructure with `clickhousectl`; no
console-clicking walkthrough is required after account authentication.

## Make the lifecycle explicit

This example publishes a completed report, not a job that must be atomically
claimed by one of many workers. The application writes two tables:

| Table | Purpose | Logical identity |
| --- | --- | --- |
| `report_results` | Typed analytical rows, such as region, category, units and revenue | Tenant, immutable run ID, row number |
| `report_runs` | Completion time, report type, file URIs, expected row count and summary | Tenant, immutable run ID |

Files remain in the filesystem for the demo, or in object storage in a deployed
application. ClickHouse stores their references, not uploaded file bytes. A
shared application needs shared object storage; a local `file://` URI is not a
public download link.

The report ID hashes the canonical input. An exact replay has the same ID; a
changed report is a new immutable run. That rule avoids an ambiguous “update the
old report but perhaps keep its old result rows” operation.

## Provision from the terminal

[Sign up for ClickHouse Cloud](https://console.clickhouse.cloud/signUp) to try
this example. New accounts start with **$300 in free credits for a 30-day trial**;
see the [current trial offer](https://clickhouse.com/cloud). If you already have
an account, use it for the steps below.

### 1. Clone the repository and enter the example

You need Git, Node.js 22 or newer, and npm. Start by cloning the repository and
entering the example directory:

```sh
git clone https://github.com/ClickHouse/examples.git
git -C examples switch --track origin/add-report-history-example
cd examples/applications/report-history
npm ci
```

The branch checkout is needed while the example PR is under review; omit it
after the example merges into `main`. Stay in `examples/applications/report-history`
for authentication and all subsequent commands, including after opening a new
terminal.

Install the [ClickHouse CLI](https://github.com/ClickHouse/clickhousectl) if
needed. Review the installer according to your organization's policy first:

```sh
curl -fsSL https://clickhouse.com/cli | sh
export PATH="$HOME/.local/bin:$PATH"
clickhousectl --version
```

### 2. Authenticate from the example directory

Create a Cloud API key with the **Admin** role for your organization using the
[API-key guide](https://clickhouse.com/docs/products/cloud/features/admin-features/api/openapi).
Keep both the Key ID and Key Secret. This example needs permission to create a
service and provision a per-service Query API key during schema setup.

In a private terminal, still in `examples/applications/report-history`, run:

```sh
clickhousectl cloud auth login --interactive
clickhousectl cloud auth status
clickhousectl cloud org list
```

Enter the Key ID and Key Secret at the prompts. Check that status shows API-key
authentication and the organization list contains your intended organization
before continuing. Browser-only OAuth login is read-only and cannot perform
this setup. Do not paste secrets into an agent conversation or commit credential
files. If an agent is running the remaining steps, complete the interactive login
yourself in a terminal in this same directory first.

### 3. Create the service and schema

From the same directory, set your public outbound IP and provision the service:

```sh
export REPORT_DEMO_IP='YOUR_PUBLIC_IP'
npm run cloud:create
npm run cloud:setup
```

The helper creates one IP-restricted AWS `eu-west-1` service with one fixed
8 GiB replica and idle scaling enabled. This configuration is for a demo, not
a high-availability recommendation. Usage draws down available trial credits;
paid accounts incur normal Cloud charges. Check your credit balance and stop
the service when you finish.

Setup applies the SQL files and creates a dedicated application user with only
`SELECT` and `INSERT` on the three example tables. It writes credentials to a
gitignored private `.env`; the application never uses the default administrator.
If creation times out, the helper records that an attempt occurred so a retry
does not silently create another service.

## Publish results before advertising completion

The worker awaits each result batch, then writes the completed-run marker:

```ts
const report = prepareReport(input);
await store.writeResults(report);
await store.writeCompletion(report);
```

This is an application publication protocol, **not a cross-table transaction**.
If the process stops between the two operations, the result rows exist but the
run is not advertised. Retrying the same input finishes publication. Reads also
check that the marker's expected row count matches the logical result count;
a marker with missing rows stays hidden.

Stable batch contents, ordering, and deduplication tokens handle ordinary
retries. ClickHouse's insert-deduplication history is finite, so the design does
not call it permanent exactly-once delivery. Both tables use
`ReplacingMergeTree`, and queries use `FINAL` to deduplicate visible logical
rows even when repeated physical rows remain. The integration test deliberately
disables insert deduplication for one replay and checks that totals do not
double. [Retry deduplication reference](https://clickhouse.com/docs/concepts/features/operations/insert/deduplicating-inserts-on-retries)

`FINAL` does not mean “wait for the background merge.” It applies the table's
replacement rules during the query. It also does not make another replica
current by itself: this Cloud example enables `select_sequential_consistency`
for acknowledged-write reads through the HTTPS endpoint. That has coordination
cost and does not create a transaction across the tables.
[ReplacingMergeTree reference](https://clickhouse.com/docs/reference/engines/table-engines/mergetree-family/replacingmergetree)
and [read-consistency guidance](https://clickhouse.com/docs/resources/support-center/knowledge-base/data-management/read-consistency)

## Query across runs, not only by report ID

The result columns support aggregate queries over many completed reports:

```sql
SELECT
    toDate(r.completed_at) AS day,
    d.region,
    d.category,
    uniqExact(d.run_id) AS reports,
    sum(d.revenue_cents) AS revenue_cents
FROM report_results AS d FINAL
INNER JOIN report_runs AS r FINAL USING (tenant_id, run_id)
WHERE d.tenant_id = {tenant:String}
GROUP BY day, d.region, d.category
ORDER BY day, d.region, d.category
```

This shortened query shows the analytical shape. The runnable `analytics()`
method additionally gates the joined runs by expected-versus-actual row count;
use that implementation when incomplete publication is possible. Integer cents
avoid floating-point currency arithmetic, and the client returns 64-bit
aggregates as strings.

Run `npm run demo`, `npm run history`, and `npm run analytics`. The demo generates
CSV inputs, parses them, writes separate Markdown reports, and stores 2,000
analytical rows for each report. No LLM key is needed: the deterministic generator
isolates the storage lifecycle. It deliberately republishes each report. The
logical result remains three reports, 6,000 rows and 7,197,000 cents of revenue.

## A status display is optional—and not a queue

If users also want progress observations, the example includes a separate
`run_status` table with `ReplacingMergeTree(version)`. A single workflow owner
assigns monotonically increasing versions. `FINAL` returns version 3 even if
version 2 arrives afterward:

```ts
await store.status(tenant, runId, 3, 'completed', completedAt);
await store.status(tenant, runId, 2, 'running', startedAt);
const current = await store.currentStatus(tenant, runId);
```

Repeated versions must have identical values. This does not implement
compare-and-swap, concurrent job claiming, or atomic state transitions. Use a
transactional service such as [ClickHouse Managed Postgres](https://clickhouse.com/cloud/postgres)
within ClickHouse Cloud if those requirements are central. A workflow ID assigned before execution can
identify progress observations; the immutable report ID is only available once
the completed payload is known.

## What the example proves—and what remains yours

The companion was verified on ClickHouse 26.2.1.641 in ClickHouse Cloud with actual CLI service
creation, a restricted application user, and integration tests for retries,
partial publication, empty reports, duplicate rows, cross-run totals, and late
status observations. It is not a scale benchmark: it accepts at most 100,000
rows per report, buffers input in memory, and recounts tenant results for completeness checks. A large
deployment needs narrower query windows, representative measurements, and an
appropriate manifest/reconciliation strategy.

The application still owns authorization, file storage, retries, batching,
orphan cleanup and workload sizing. Tenant filtering in example queries is not
database-enforced isolation: the shared server-side user can access every
example tenant. Do not expose it directly to a browser or an untrusted client.

Finish with `npm run cloud:stop`. Stopping preserves the service and data;
storage, backups, or other applicable charges can remain. Consult current
[pricing](https://clickhouse.com/pricing) and [idling guidance](https://clickhouse.com/docs/products/cloud/features/autoscaling/idling)
instead of treating a small test as a cost or resume-latency guarantee.

The practical distinction is straightforward: completed-report history and
analytical results can be one analytical application. Transactional invariants
still deserve a transactional design. The runnable repository makes both the
working path and its boundary explicit.
