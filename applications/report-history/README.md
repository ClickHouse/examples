# Report results and run history with ClickHouse Cloud

A runnable TypeScript example for an application that generates reports, stores
their analytical result rows, retrieves a previous report, and aggregates across
completed runs. Provision the database using `clickhousectl`; the application
uses the official ClickHouse JavaScript client over HTTPS.

The main lifecycle is **completed-run inserts**, not a transactional job queue.
An optional versioned status table shows how a single workflow owner can publish
current-state observations without waiting for a background merge.

## When this design fits

- Results are append-oriented and the useful queries scan or aggregate many rows.
- A completed report is immutable. Correcting its input creates a new report ID.
- Run metadata is small relative to analytical results.
- The application can retry an interrupted publication and hide incomplete runs.

Choose a transactional store, such as [Postgres managed by ClickHouse](https://clickhouse.com/cloud/postgres),
for concurrent job claiming, compare-and-swap state transitions, uniqueness
constraints, balances, or multi-row transactions. This example does not implement
those guarantees. A Postgres application can separately send analytical results
to ClickHouse if both workloads matter.

This is an executable design example, **not a hundreds-of-millions-of-rows
benchmark or production application**. The example accepts at most 100,000 rows
per report and buffers input in memory (the CSV parser reads before validating
that row-count limit). The completeness checks intentionally prioritize understandable
correctness over optimization: they count this tenant's result rows on reads.
At large scale, add time/run filters, benchmark `FINAL` and joins with realistic
data, and design an ingestion reconciliation/manifest strategy that does not
recount the entire tenant on every history request.

## Prerequisites

- Node.js 22 or newer, npm, Git, and a ClickHouse Cloud account with billing/trial
  capacity. This example creates a chargeable Cloud service.
- An **Admin-role Cloud API key**: setup's first SQL request auto-provisions a
  per-service Query API key, which needs key-creation permission. A
  Developer-scoped key may create the service but fail that step. The
  CLI's OAuth login is read-only; it cannot perform this setup.
- Your public outbound IP address and permission to create one AWS `eu-west-1`
  service. Change provider/region in `scripts/cloud.mjs` if required.

Install the CLI, review the installer according to your organization's policy,
and verify it is on your PATH:

```sh
curl -fsSL https://clickhouse.com/cli | sh
export PATH="$HOME/.local/bin:$PATH"
clickhousectl --version
clickhousectl cloud auth status
clickhousectl cloud org list
```

If not already authenticated, use a private terminal to run:

```sh
clickhousectl cloud auth login --api-key <key-id> --api-secret <key-secret>
```

Do not commit API keys or paste them into an agent conversation. Follow the
[CLI authentication documentation](https://github.com/ClickHouse/clickhousectl)
for your environment's credential policy. Initial account/API-key issuance may
require the Cloud account administrator; everything below is CLI-driven.

## 1. Install the example

```sh
git clone https://github.com/ClickHouse/examples.git
git -C examples switch --track origin/add-report-history-example
cd examples/applications/report-history
npm ci
npm run typecheck
npm test
```

The `git switch` line checks out this contribution's review branch. Omit it once
the example has merged into `main`.

## 2. Create a bounded, IP-restricted Cloud service

Set your public outbound IP explicitly. For example, `curl -fsS
https://api.ipify.org` displays the IPv4 address seen by that external service;
only use an IP-check service approved by your organization.

```sh
export REPORT_DEMO_IP='YOUR_PUBLIC_IP'
export REPORT_DEMO_SERVICE_NAME='report-history-example'
# If you have more than one Cloud organization:
# export REPORT_DEMO_ORG_ID='YOUR_ORG_ID'
npm run cloud:create
npm run cloud:setup
```

The helper runs this real CLI command, capturing the one-time password securely
instead of printing it into an agent transcript:

```sh
clickhousectl cloud service create \
  --name report-history-example --provider aws --region eu-west-1 \
  --min-replica-memory-gb 8 --max-replica-memory-gb 8 --num-replicas 1 \
  --idle-scaling true --idle-timeout-minutes 5 \
  --ip-allow YOUR_PUBLIC_IP/32 --tag example=report-history --json
```

For IPv6, the helper uses `/128` instead of `/32`. It never opens access to
`0.0.0.0/0`. One fixed 8 GiB replica bounds compute size; this is a demo setting,
not a high-availability recommendation. Five minutes is the configured minimum
idle timeout, not a promise that Cloud will always suspend at exactly five
minutes. See [idling behavior](https://clickhouse.com/docs/products/cloud/features/autoscaling/idling)
and [current pricing](https://clickhouse.com/pricing).

`cloud:setup` waits up to ten minutes for running state, then applies one SQL
statement per CLI invocation, for example:

```sh
clickhousectl cloud service query --id YOUR_SERVICE_ID \
  --queries-file sql/01-database.sql
clickhousectl cloud service query --id YOUR_SERVICE_ID \
  --queries-file sql/02-results.sql
```

It also applies `03-runs.sql` and `04-status.sql`, generates a policy-compliant
random password, saves it **before** creating the user, and grants only
`SELECT, INSERT` on the example's three tables to `report_history_app`.
Application credentials are in `.env`; the initial admin response is in
`.cloud-create-response.json`. Both are gitignored and created with mode `0600`.
The runtime never uses the `default` administrator or a Cloud API key.

The service ID is saved in `.cloud-service.json`. Setup is resumable. A create
timeout may still have created a service: `.cloud-create-intent.json` prevents
blind duplicate creation. Inspect `clickhousectl cloud service list`, confirm
the intended service, and run `node scripts/cloud.mjs recover YOUR_SERVICE_ID`.
Do not erase the intent and retry creation without checking.

## 3. Publish and query reports

```sh
npm run demo
npm run history
npm run analytics
npm run test:integration
```

The demo generates three CSV source files, reads them through a real CSV parser,
writes three separate human-readable Markdown reports, inserts 2,000 analytical
rows per report in batches, and deliberately republishes each report. The report
generator is deterministic: no LLM API key or inference service is needed. You
should see **three completed reports and 6,000 logical result rows**, not six
reports or doubled totals. Revenue across the demo reports is **7,197,000 cents**.
Files live in `.local/`; ClickHouse stores their URIs, metadata, and result rows,
not the file bytes. Production shared artifacts should live in your object
store; this example does not provision a bucket or make local paths accessible
to another machine.

Use the store from your own TypeScript worker:

```ts
import { connect, ReportStore } from './src/store.ts';

const client = connect();
try {
  const store = new ReportStore(client);
  const runId = await store.publish({
    tenant_id: 'team-a',
    completed_at: '2026-08-01T12:00:00.000Z', // preserve on retry
    report_type: 'sales-summary',
    source_uri: 's3://your-bucket/source.csv',
    artifact_uri: 's3://your-bucket/report.json', // upload before publishing
    rows: [{ region: 'eu', category: 'software', revenue_cents: 1200, units: 2 }],
  });
  console.log(await store.report('team-a', runId));
  console.log(await store.analytics('team-a'));
} finally {
  await client.close();
}
```

The example uses integer cents instead of floating-point currency. Client
outputs preserve 64-bit integer aggregates as strings. `summary_json` is a small
serialized summary for display, while typed columns support the analytical
queries; it is not an assertion that ClickHouse requires JSON flattening.

## Publication, retries, and query correctness

1. Compute a SHA-256 run ID from canonical immutable input, including tenant,
   timestamp, file URIs, row values, and row order. Preserve that exact input
   across retries. A different timestamp, URI, or result creates a different run.
2. Insert result rows in stable 1,000-row chunks, awaiting each acknowledgment.
3. Only then insert a completed-run marker with the expected row count.
4. Reads use `FINAL` on both tables and expose a run only when its distinct
   logical result count matches the marker.

These are separate inserts, **not a cross-table transaction**. If the process
stops after step 2, results exist without a visible report. Rerun the same
publication to finish it. A marker without all expected results is hidden as
well. Orphaned partial runs are retained; scheduling reconciliation and cleanup
is a production responsibility, not an automatic feature of this demo.

The application retries selected transient connection failures and the pinned
client's request-timeout error on inserts, with bounded exponential backoff.
Read helpers surface errors to their caller rather than automatically retrying.
SQL/authentication errors fail immediately. An exhausted
timeout does **not** prove the insert failed: preserve the original input and
replay it later. Query requests have a 60-second client timeout and a 30-second
server execution limit; the demo does not promise a resume-time SLA.

`insert_deduplication_token` suppresses repeated chunks within ClickHouse's
finite deduplication window. That window is **not permanent exactly-once
delivery**. The `ReplacingMergeTree` keys plus `FINAL` keep logical reads
deduplicated even if physical duplicates are inserted later. This assumes the
same immutable contents for a given run ID and row number; it is not a
database-enforced uniqueness constraint or protection against malicious writers.
Do not copy a token onto different data, change chunk size on retry, or aggregate
raw unfinalized rows when correctness depends on deduplication.

`FINAL` resolves versions visible to a query; it does not itself synchronize
replicas. This Cloud example additionally sets `select_sequential_consistency=1`
for acknowledged-write reads through the HTTPS load balancer. That setting has
coordination overhead and is not a substitute for multi-table transactions.

References: [retry deduplication](https://clickhouse.com/docs/concepts/features/operations/insert/deduplicating-inserts-on-retries),
[ReplacingMergeTree](https://clickhouse.com/docs/reference/engines/table-engines/mergetree-family/replacingmergetree),
and [read consistency](https://clickhouse.com/docs/resources/support-center/knowledge-base/data-management/read-consistency).

## Optional status observations

The core example does not need a mutable job row: it records a report after the
worker has completed its work. If you also want a progress display, `run_status`
uses `ReplacingMergeTree(version)` and `currentStatus()` reads with `FINAL`.

```ts
await store.status('team-a', runId, 3, 'completed', '2026-08-01T12:00:00.000Z');
// A late delivery of an earlier observation must not roll the status backward:
await store.status('team-a', runId, 2, 'running', '2026-08-01T11:59:00.000Z');
console.log(await store.currentStatus('team-a', runId)); // completed, version 3
```

A **single workflow owner** allocates strictly increasing versions; retries of
one version must contain identical values. Equal-version conflicts are not
resolved as a business invariant. This table is neither a locking primitive nor
a transactional queue. Batch status observations in a busy application; avoid
creating a separate synchronous insert for every high-frequency progress tick.
Use a stable external workflow ID if you need statuses before the final
content-addressed report ID exists; retain the mapping in your application.

## Security, operations, and verification

This is a server-side CLI example, not a browser endpoint. It does not implement
login, HTTP authentication, per-tenant RBAC, quotas, or public API rate limiting.
Tenant parameters prevent accidental mixing in these query helpers, but the
shared application user can read/write **all** example tenants. Add suitable
authorization or separate users/row policies before exposing it to untrusted
callers. Never ship `.env` to a browser.

Cloud operates database infrastructure, but the application still owns schema,
access control, batching, retries, file retention, reconciliation, and workload
sizing. There is no background worker, message broker, dashboard, or paid third-
party dependency hidden in this example.

Verified on 2026-09-05 with `clickhousectl 0.4.2`, Node.js 25.9.0,
`@clickhouse/client 1.23.1`, and ClickHouse Cloud 26.2.1.641:

- Type checking and six offline unit tests, including CSV-to-Markdown generation,
  timeout retries and exact money sums.
- Live integration: interrupted publication, stable replay, forced physical
  duplicates, incomplete-marker gating, empty reports, two-run analytics,
  tenant-filtered queries, and out-of-order status versions.
- The restricted application user was denied `CREATE TABLE` (an expected
  `ACCESS_DENIED` log appears during the integration test).
- End-to-end demo published three reports and queried all 6,000 result rows.

These are functional tests on a small service, not measurements of throughput,
cost at scale, cold starts, or high availability. Integration tests use unique
tenant IDs and retain their small synthetic datasets for inspection.

## Stop the service when finished

```sh
npm run cloud:stop
# Later:
clickhousectl cloud service start YOUR_SERVICE_ID
```

Stopping retains data and does not remove the service. Storage, backups, or other
applicable charges can continue; check current Cloud billing. A stopped service
needs an explicit start. An idle service can resume on a query.

If you no longer need the data, inspect the recorded ID and explicitly delete
that service with `clickhousectl cloud service delete YOUR_SERVICE_ID`. Deletion
is destructive; the example never performs it automatically.

See [engineering-resource-draft.md](engineering-resource-draft.md) for a proposed
companion article explaining the design and its boundaries.
