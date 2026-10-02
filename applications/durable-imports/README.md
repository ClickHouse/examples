# Durable contact imports

An Express API accepts a small contact import, immediately returns its identifier, and lets its account retrieve progress and results. A separate pg-boss worker processes the durable payload in ClickHouse Managed Postgres. No email is sent and no external service is called.

The important boundaries are visible in the code:

- [Submission](src/imports.ts) inserts the import and enqueues its job on the **same node-postgres client transaction**, using pg-boss's `Db.executeSql` adapter. Account locking coordinates quotas and concurrent request retries.
- [The worker](src/handler.ts) receives pg-boss's transaction through `transactional: true`. Contact rows, application completion and queue completion commit together. A thrown error or killed process rolls back the handler writes; the already claimed job can be retried.
- Database uniqueness on `(account_id, request_id)`, `(import_id, email)` and `(import_id, row_index)` backs up the application coordination. Contacts are **import-scoped results**: the same email in distinct imports is allowed.

This example pins Node 24.21.0, Express 5.2.1, node-postgres 8.23.1 and pg-boss 12.35.1. The queue schema is migrated separately with its owner. Runtime startup never performs DDL.

## Create a Cloud fixture

Use a dedicated test service. The shape below was verified for AWS `us-east-1`; inspect current availability and pricing before creating your own. This example uses PostgreSQL 18 without HA.

```bash
export ORG_ID=your-organization-id
clickhousectl cloud postgres create --org-id "$ORG_ID" \
  --name durable-imports --provider aws --region us-east-1 \
  --size c6gd.large --pg-version 18 --ha-type none --json \
  > /private/path/service.json
chmod 600 /private/path/service.json
```

Save the returned service ID, hostname, port, username and password privately. Creation is asynchronous. Repeat the following until its status is `running`:

```bash
export SERVICE_ID=your-created-service-id
clickhousectl cloud postgres get "$SERVICE_ID" --org-id "$ORG_ID" --json
clickhousectl cloud postgres certs get "$SERVICE_ID" --org-id "$ORG_ID" \
  --output /private/path/cloud-ca.pem
```

See the [ClickHouse Managed Postgres documentation](https://clickhouse.com/docs/products/managed-postgres/). A running service incurs charges; deleting it after testing avoids continuing charges. Keep the CLI receipt out of Git and logs.

## Install and explicitly migrate

Install the pinned Node release and PostgreSQL client in your development environment. From this directory:

```bash
npm ci --ignore-scripts
npm run build
npm test
```

Create a private setup environment file. Use the Cloud receipt for the administrator, and generate three distinct random database passwords of at least 24 characters. Use separate random URL-safe tokens of 32–128 characters for the seeded accounts.

```dotenv
PGHOST=your-service-hostname
PGPORT=5432
PGDATABASE=postgres
PGSSLROOTCERT=/absolute/path/cloud-ca.pem
PGSSLMODE=verify-full
ADMIN_USER=receipt-username
ADMIN_PASSWORD=receipt-password
MIGRATION_PASSWORD=distinct-random-owner-password
APP_PASSWORD=distinct-random-api-password
WORKER_PASSWORD=distinct-random-worker-password
CASEY_TOKEN=distinct-random-account-token
MORGAN_TOKEN=another-random-account-token
```

Export these fields to child processes, then bootstrap as the administrator:

```bash
set -a
source /private/path/setup.env
set +a
export PGUSER="$ADMIN_USER" PGPASSWORD="$ADMIN_PASSWORD"
psql -X -f sql/bootstrap.sql
export PGUSER=imports_migration PGPASSWORD="$MIGRATION_PASSWORD"
psql -X -f sql/migrate.sql
psql -X -f sql/seed.sql
npm run db:queue
psql -X -f sql/grants.sql
```

`bootstrap.sql` creates the roles and owned schemas once. It revokes public schema creation on this dedicated fixture. `migrate.sql`, `seed.sql` and `db:queue` are repeatable; rerun them to check the setup. The owner command invokes the pinned pg-boss migrations and creates a nonpartitioned queue. It omits the immutable `partition` option from later queue updates. No database `CREATE` grant is needed because the administrator already created both schemas.

For migration upgrades, stop workers, inspect the pinned library's migration plans, run the owner command and review the grants against that release before restarting. Changing the dependency alone does not migrate runtime databases. Application migration version 1 has a destructive dedicated-fixture reset rather than a production downgrade path.

### Runtime permissions

`imports_api` may read application records, update the account quota columns, insert imports, reconcile terminal failures, and insert jobs into the owned queue's shared partition. It cannot claim jobs or insert contact results.

`imports_worker` may read the payload, insert results, update application outcomes, claim/settle/delete queue jobs, update queue maintenance metadata, and clean queue dependencies. Two column grants on `import_jobs.version` allow the flow and monitoring cadence gates; its actual schema version remains immutable. Both roles can execute `job_now()`. They cannot create schemas, tables, queues or partitions, truncate tables, rewrite payloads, change existing contact results, or rebuild indexes.

Ordinary worker supervision stays enabled for expiry, retries and retention. Scheduling, persistent statistics/warning partitions and automatic index rebuilding are disabled to avoid runtime DDL. Index maintenance and library upgrades belong to the owner. These grants are specific to pg-boss 12.35.1, not a universal pg-boss permission recipe.

The runtime credentials are trusted shared application roles. Account isolation is enforced by server queries and token mappings, not PostgreSQL row-level security; a holder of those database credentials can access other accounts' rows within the granted permissions.

## Run the API and worker

Create separate private runtime files containing only connection fields, the respective role/password, and `PORT=4000`. The API file also contains `CASEY_TOKEN` and `MORGAN_TOKEN`; the worker does not need those tokens. Use [.env.example](.env.example) as a template. Do not copy administrator or migration credentials into runtime files.

In one shell:

```bash
set -a; source /private/path/api.env; set +a
unset ADMIN_USER ADMIN_PASSWORD MIGRATION_PASSWORD APP_PASSWORD WORKER_PASSWORD
npm start
```

In another:

```bash
set -a; source /private/path/worker.env; set +a
unset ADMIN_USER ADMIN_PASSWORD MIGRATION_PASSWORD APP_PASSWORD WORKER_PASSWORD
npm run worker
```

The API binds to `127.0.0.1`. Both clients verify the Cloud CA and hostname explicitly; `PGSSLMODE` also configures `psql`. There is no option to disable verification.

Tokens map to Casey and Morgan's seeded account IDs on the server. Requests cannot set their owner. Tokens are bearer credentials, not passwords, browser sessions or a user-management system. Rotating them requires restarting the API with new configuration. There is no cookie authentication or CORS configuration. Public deployment would need HTTPS termination, credential management and traffic controls beyond this loopback example.

## Submit, poll and read results

Use synthetic contacts only. Keep the same request UUID when retrying the same submission:

```bash
export REQUEST_ID=12345678-1234-4234-8234-123456789abc
curl -sS http://127.0.0.1:4000/imports \
  -H "Authorization: Bearer $CASEY_TOKEN" -H 'Content-Type: application/json' \
  -d '{"requestId":"12345678-1234-4234-8234-123456789abc","rows":[{"email":" Casey@Example.test ","name":" Casey   Example "}]}'
# Copy the returned import ID:
export IMPORT_ID=returned-import-id
curl -sS "http://127.0.0.1:4000/imports/$IMPORT_ID" \
  -H "Authorization: Bearer $CASEY_TOKEN"
curl -sS "http://127.0.0.1:4000/imports/$IMPORT_ID/results" \
  -H "Authorization: Bearer $CASEY_TOKEN"
```

| Route | Result |
| --- | --- |
| `POST /imports` | `202` on creation; `200` for a matching retained request; `409` for different normalized content with the same account/request ID |
| `GET /imports/:id` | Account-scoped state, queue progress, row count and terminal error/result count; `404` for missing or foreign records |
| `GET /imports/:id/results` | Up to 100 ordered normalized rows after success; `409` before success |

Bodies are capped at 64 KiB and 1–100 rows. Only the documented fields are accepted. Email normalization trims and lowercases a deliberately basic ASCII syntax; it does **not** validate deliverability. Names are NFKC normalized, trimmed, whitespace collapsed, and limited to 80 Unicode codepoints. NUL, invalid Unicode and duplicate normalized emails in one import are rejected. Fingerprints retain row order, so a reordered retry conflicts.

An account may have five pending imports and submit 50 new imports per account quota window. The window resets on the first new submission at least 24 hours after its stored start. Matching retries neither reset the window nor consume another slot. This is a resettable fixed window, not a sliding 24-hour count. Quota rejection is `429`; `Retry-After: 60` is a suggested polling delay, not a guarantee that quota will be available in a minute. Input errors are `400` or `413`; authentication failures are `401`.

## Retries and durable outcomes

The queue permits an initial attempt plus two retries, with one-second exponential backoff capped at four seconds. Claims expire after 20 seconds and heartbeat every 10 seconds. Handlers have a 25-second database transaction limit; imports are deliberately short and bounded. Each process has one local handler and a five-connection queue pool, separate from its five-connection application pool.

A worker exception rolls back contacts, application success and queue completion together. The claim itself was committed earlier, so supervision can move an abandoned attempt back to retry. Multiple executions can occur; the handler checks the durable import state and database constraints prevent duplicate import-scoped effects. This does not provide exactly-once email, payment or other external effects.

Queued jobs have one-hour retention and terminal job metadata is deleted after one day. The application reconciles queue failures/cancellations into durable terminal records on worker startup, periodic worker ticks, submission and status reads. If metadata disappears before reconciliation, it reports `Queue metadata no longer available`, not a fabricated cause or perpetual processing. Durable payloads, request fingerprints and results have no application purge route in this small example; operators need a retention policy for a production system.

## Real Cloud acceptance

Cloud tests require the setup environment plus `PGUSER=imports_api` and its password. They create records, use owner credentials for isolated fault/retention fixtures, and start runtime-only child processes. Use a dedicated service and run from a freshly bootstrapped schema:

```bash
set -a; source /private/path/setup.env; set +a
export PGUSER=imports_api PGPASSWORD="$APP_PASSWORD"
npm run test:cloud
```

The tests exercise verified TLS controls, forbidden runtime DDL and mutations, atomic enqueue rollback, eight competing request retries, two worker processes, quotas, transactional handler failure, retry exhaustion, runtime retention, an actual `SIGKILL` after uncommitted effects, completion replay, account-scoped HTTP behavior and confirmed API/worker restarts. The faults are bounded, require `NODE_ENV=test`, and cannot be requested through HTTP. Private acceptance logs are kept outside the repository.

## Cleanup

Stop API and worker processes first. To reset only this dedicated fixture's schemas/roles, explicitly restore administrator credentials in a setup shell:

```bash
set -a; source /private/path/setup.env; set +a
export PGUSER="$ADMIN_USER" PGPASSWORD="$ADMIN_PASSWORD"
psql -X -f sql/cleanup.sql
```

To remove your Cloud fixture, use its exact saved ID and verify that it disappears from the organization listing:

```bash
clickhousectl cloud postgres delete "$SERVICE_ID" --org-id "$ORG_ID"
clickhousectl cloud postgres list --org-id "$ORG_ID" --json
```

Deletion is asynchronous and destroys the service's data. Retain needed source/evidence before deleting it.

## Primary references

- [pg-boss transaction adapters](https://pgboss.io/api/adapters)
- [pg-boss transactional workers](https://pgboss.io/api/workers)
- [Pinned pg-boss 12.35.1 source](https://github.com/timgit/pg-boss/tree/12.35.1)
- [node-postgres transactions](https://node-postgres.com/features/transactions)
- [Express API](https://expressjs.com/en/5x/api.html)
