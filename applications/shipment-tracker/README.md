# NestJS shipment tracker

A small account-scoped API tracks seeded shipments through `created → dispatched → delivered`, with cancellation from `created` or `dispatched`. ClickHouse Managed Postgres stores current state and immutable accepted transition events. ClickPipes copies those events to analytical ClickHouse; the official Node.js client reads bounded delivery reports. All database services run in ClickHouse Cloud. There is no carrier, address, payment or tracking-provider integration.

Shipment creation is a seed/admin operation. The HTTP API provides reads, history and lifecycle transitions. A static server-configured bearer token identifies an account; callers cannot choose their account. The server binds to loopback by default. Deploy behind trusted HTTPS and replace demo tokens with proper identity and access policies before public use.

## Workflow and boundaries

| Route | Behavior |
|---|---|
| `GET /shipments?limit=20&after=<UUID>` | Account-scoped live UUID keyset pagination; maximum 50 rows |
| `GET /shipments/:id` | Current authoritative Postgres state or 404 |
| `GET /shipments/:id/events?limit=20&afterRevision=0` | Account-scoped accepted history; maximum 50 rows |
| `POST /shipments/:id/transitions` | 201 for a new event; 200 for an identical retained retry; 409 for stale revision, invalid lifecycle or reused ID with different data |
| `GET /reports?from=YYYY-MM-DD&to=YYYY-MM-DD` | Eventually consistent daily transition/delivery summaries for the authenticated account |

A transition body contains only `requestId`, integer `expectedRevision` and `toStatus`. Request IDs contain 1–64 ASCII letters, digits, `.`, `_` or `-`. The revision range is 0–9,999 on input. Bodies are limited to 4 KiB, unknown fields are rejected, and malformed JSON returns 400. UUID paths are normalized to lowercase for matching retries.

The transaction locks the account, checks its retained request ID, then locks the scoped shipment. It checks the supplied revision and lifecycle, updates the shipment and inserts the event using **that transaction's TypeORM manager**. A failed insert rolls back the earlier update. The same ID and data return the original event even after later transitions or process restart. Changing the shipment, expected revision or target status conflicts. IDs are unique across all shipments and dates within one account and retained indefinitely here. Deleting events would release retry protection; production retention needs an explicit coordinated policy. After a lost response, retry the same data and ID: the first observed success may be 200.

Account-first locking serializes every transition for one account, including transitions of different shipments. It keeps account-wide retry semantics simple; different accounts can progress independently. Every transaction uses the same lock order. No throughput claim is made. The shared runtime role is trusted application code, not a database tenant boundary: HTTP authentication supplies account scope. Do not distribute database credentials to clients.

A single server timestamp is captured after the locks. Accepted event time and UTC `event_day` derive from it. Dispatch records this timestamp on the shipment and event. Delivery copies the dispatch timestamp and records the integer millisecond difference in its terminal event. This measures elapsed time between **API-accepted** dispatch and delivery, not a carrier measurement; it can cross UTC midnight. Clock movement that would produce a negative duration rejects the transition. Non-delivered events use zero and are excluded from duration aggregates.

The list sorts by immutable UUID, not mutable status/time. Inserts whose UUID precedes a cursor are absent from later pages; this is live traversal, not a snapshot. History sorts by per-shipment revision. Delivered and cancelled states are terminal.

## Build

Use Node.js 24.21.0, npm 11.19.0, `psql`, OpenSSL, curl, jq and [clickhousectl](https://clickhouse.com/docs/concepts/features/interfaces/cli). Run commands from this directory in Linux. `.node-version` and `package-lock.json` pin the runtime intent and dependency graph; no database credentials are needed:

```sh
npm ci
npm run typecheck
npm test
```

The verified stack is NestJS 12.1.2, its TypeORM adapter 12.0.2, TypeORM 1.1.1, node-postgres 8.23.1, TypeScript 7.0.2 and `@clickhouse/client` 1.23.1. Four unit tests cover strict inputs, lifecycle/duration/UTC boundaries and token identity. Nest's modules, guard, validation pipe and TypeORM integration are used directly; entity schemas describe rows. `synchronize: false` and explicit migrations keep startup separate from schema changes. See [Nest's transaction and migration guidance](https://docs.nestjs.com/data/typeorm).

The PG pool has five connections, a 10-second connection limit, 20-second statement timeout and 25-second query timeout. These are layer controls, not an HTTP response-time promise. Temporary failures return a generic 503 without SQL or credentials in the response. Operational startup does not require an analytical query to succeed.

## Create the Cloud services

These resources incur charges. Use dedicated names, protect receipts, and delete your resources after validation. The tested small PG shape is `c6gd.large`, AWS `us-east-1`, PostgreSQL 18 with no HA. Check current availability and pricing. The analytical service uses the CLI's current minimum 8 GiB per replica, with two replicas for a new warehouse.

```sh
umask 077
mkdir -p .deployment
export ORG_ID='your-organization-id'
export DEV_EGRESS_IP='your-development-public-egress-ip'
clickhousectl cloud postgres create --org-id "$ORG_ID" \
  --name shipment-tracker-pg --provider aws --region us-east-1 \
  --size c6gd.large --pg-version 18 --ha-type none --json \
  > .deployment/postgres-create.json
export PG_ID=$(jq -er .id .deployment/postgres-create.json)
clickhousectl cloud service create --org-id "$ORG_ID" \
  --name shipment-tracker-analytics --provider aws --region us-east-1 \
  --min-replica-memory-gb 8 --max-replica-memory-gb 8 --num-replicas 2 \
  --idle-scaling false --ip-allow "$DEV_EGRESS_IP/32=shipment-tracker-dev" --json \
  > .deployment/clickhouse-create.json
export CH_ID=$(jq -er .service.id .deployment/clickhouse-create.json)
```

Poll `cloud postgres get "$PG_ID"` and `cloud service get "$CH_ID"`, with `--org-id "$ORG_ID" --json`, until both states are `running`. Use a finite deadline, for example ten minutes, and stop on failure. `get` does not return the original passwords. Restrict the analytical allowlist to your development egress; ClickPipes manages its destination connectivity. Keep Cloud organization API credentials out of application runtime files.

## Bootstrap roles, migrations and seed

```sh
clickhousectl cloud postgres certs get "$PG_ID" --org-id "$ORG_ID" \
  --output .deployment/postgres-ca.pem
export PGHOST=$(jq -er .hostname .deployment/postgres-create.json)
export PGPORT=5432 PGDATABASE=postgres PGSSLMODE=verify-full
export PGSSLROOTCERT="$PWD/.deployment/postgres-ca.pem"
export PGADMIN=$(jq -er .username .deployment/postgres-create.json)
export PGPASSWORD=$(jq -er .password .deployment/postgres-create.json)
export SHIPMENTS_MIGRATOR_PASSWORD="Aa1_$(openssl rand -hex 24)"
export SHIPMENTS_APP_PASSWORD="Aa1_$(openssl rand -hex 24)"
export SHIPMENTS_CDC_PASSWORD="Aa1_$(openssl rand -hex 24)"
psql -X -v ON_ERROR_STOP=1 -U "$PGADMIN" -f sql/bootstrap.sql
PGUSER=shipments_migrator PGPASSWORD="$SHIPMENTS_MIGRATOR_PASSWORD" npm run migrate
PGUSER=shipments_migrator PGPASSWORD="$SHIPMENTS_MIGRATOR_PASSWORD" npm run seed
psql -X -v ON_ERROR_STOP=1 -U "$PGADMIN" -f sql/publication.sql
```

Bootstrap creates a non-login schema owner, a migration login, a runtime login and an event-only replication login. The migrator assumes the owner for schema/seed operations. Run bootstrap once. Repeating `migrate` is a no-op; repeating `seed` preserves current state. Seed creates six shipments in the North account and three in the South account. Account/shipment UUIDs are visible in `src/admin.ts`.

`PGUSER=shipments_migrator PGPASSWORD="$SHIPMENTS_MIGRATOR_PASSWORD" npm run revert` drops all application tables and data. A lifecycle check belongs **before** accepted events and pipe creation: revert, migrate and seed again. If publication already exists, dropping its table removes membership; restore it with administrator credentials using `ALTER PUBLICATION shipments_events_clickpipe ADD TABLE shipments.events` instead of rerunning the publication creation script.

Runtime can read accounts/shipments/events, update only current-state fields, insert events, and lock account rows using a narrowly granted `UPDATE(account_id)`. It cannot create tables, create shipments, update/delete events or access migration history. The composite account/shipment foreign key rejects cross-account event linkage. SQL CHECKs enforce lifecycle, UTC day, revision relationship and dispatch/delivery timestamp facts. Publication contains **only** events; accounts, credentials and current-state rows are not copied.

## Analytical reader and runtime configuration

```sh
export CLICKHOUSE_URL="https://$(jq -er '.service.endpoints[] | select(.protocol=="https") | .host' .deployment/clickhouse-create.json):$(jq -er '.service.endpoints[] | select(.protocol=="https") | .port' .deployment/clickhouse-create.json)"
export CH_REPORT_PASSWORD="Aa1_$(openssl rand -hex 24)"
printf 'url="%s/?max_execution_time=10&max_rows_to_read=1000000&max_bytes_to_read=100000000"\nuser="default:%s"\nfail-with-body\nsilent\nshow-error\n' \
  "$CLICKHOUSE_URL" "$(jq -er .password .deployment/clickhouse-create.json)" \
  > .deployment/ch-admin.conf
printf "CREATE USER shipments_reports IDENTIFIED BY '%s' SETTINGS readonly=2, max_execution_time=5, max_rows_to_read=1000000, max_bytes_to_read=100000000, max_result_rows=186, result_overflow_mode='throw', max_threads=2;" \
  "$CH_REPORT_PASSWORD" > .deployment/report-user.sql
curl --max-time 20 --config .deployment/ch-admin.conf --data-binary @.deployment/report-user.sql
export TOKEN_A=$(openssl rand -hex 32) TOKEN_B=$(openssl rand -hex 32)
export ACCOUNT_TOKENS=$(jq -cn --arg a "$TOKEN_A" --arg b "$TOKEN_B" \
  '{"00000000-0000-4000-8000-000000000001":$a,"00000000-0000-4000-8000-000000000002":$b}')
{
  printf 'export PGHOST=%q PGPORT=5432 PGDATABASE=postgres PGUSER=shipments_app\n' "$PGHOST"
  printf 'export PGPASSWORD=%q PGSSLROOTCERT=%q\n' "$SHIPMENTS_APP_PASSWORD" "$PGSSLROOTCERT"
  printf 'export CLICKHOUSE_URL=%q CLICKHOUSE_USER=shipments_reports CLICKHOUSE_PASSWORD=%q\n' "$CLICKHOUSE_URL" "$CH_REPORT_PASSWORD"
  printf 'export ACCOUNT_TOKENS=%q\n' "$ACCOUNT_TOKENS"
} > .deployment/app.env
{
  printf 'export SHIPMENTS_MIGRATOR_PASSWORD=%q\n' "$SHIPMENTS_MIGRATOR_PASSWORD"
  printf 'export SHIPMENTS_CDC_PASSWORD=%q\n' "$SHIPMENTS_CDC_PASSWORD"
} > .deployment/test-secrets.env
```

`readonly=2` prohibits writes while permitting bounded query settings. Grant table-only SELECT after ClickPipes creates the destination. Direct HTTPS administration creates no Cloud Query API credential. If using `cloud service query` instead, inventory and clean up its auto-created Query API credentials/endpoints; preserve the organization API key.

Start a **fresh shell**, then load only runtime credentials:

```sh
source .deployment/app.env
bash scripts/start-runtime.sh
```

The launcher whitelists runtime fields, so inherited setup credentials are excluded from the Node process. node-postgres verifies both downloaded CA and hostname (`rejectUnauthorized: true`); analytical connections use normally verified HTTPS. Both services are remote Cloud databases.

In a second shell, load `.deployment/app.env` and derive its account token:

```sh
source .deployment/app.env
export TOKEN_A=$(jq -er '."00000000-0000-4000-8000-000000000001"' <<< "$ACCOUNT_TOKENS")
curl -sS --fail-with-body -H "Authorization: Bearer $TOKEN_A" http://127.0.0.1:3000/shipments
curl -sS --fail-with-body -H "Authorization: Bearer $TOKEN_A" -H 'Content-Type: application/json' \
  -d '{"requestId":"snapshot-a-dispatch","expectedRevision":0,"toStatus":"dispatched"}' \
  http://127.0.0.1:3000/shipments/a0000000-0000-4000-8000-000000000001/transitions
curl -sS --fail-with-body -H "Authorization: Bearer $TOKEN_A" -H 'Content-Type: application/json' \
  -d '{"requestId":"snapshot-a-deliver","expectedRevision":1,"toStatus":"delivered"}' \
  http://127.0.0.1:3000/shipments/a0000000-0000-4000-8000-000000000001/transitions
```

Replaying the dispatch ID/body returns its original dispatch event with 200 even after delivery. A different ID based on revision 0 now conflicts: refetch current state before deciding a new action. Seeded shipment IDs include alphabetic characters so uppercase-path replay can be tested.

## Create and inspect the ClickPipe

Source has a NOT NULL unique replica-identity index `(account_id,event_day,event_id)`. These immutable columns also form the [custom ClickPipes ordering key](https://clickhouse.com/docs/integrations/clickpipes/postgres/ordering-keys). Dispatch timestamp is legitimately unknown before dispatch, so preserve its nullability; do not invent a sentinel timestamp.

In the setup shell, with saved resource IDs and CDC password:

```sh
clickhousectl cloud clickpipe create postgres "$CH_ID" --org-id "$ORG_ID" \
  --name shipment-tracker-events --host "$PGHOST" --port 5432 --pg-database postgres \
  --username shipments_cdc --password "$SHIPMENTS_CDC_PASSWORD" \
  --ca-certificate .deployment/postgres-ca.pem --publication-name shipments_events_clickpipe \
  --replication-mode cdc --sync-interval-seconds 10 --pull-batch-size 10000 \
  --initial-load-parallelism 1 --snapshot-parallel-tables 1 \
  --allow-nullable-columns true --delete-on-merge false \
  --table-mapping-json "$(cat infra/clickpipe-events.json)" --json \
  > .deployment/clickpipe-create.json
export PIPE_ID=$(jq -er .id .deployment/clickpipe-create.json)
```

Poll `cloud clickpipe get "$CH_ID" "$PIPE_ID" --org-id "$ORG_ID" --json` until `Running`, with a finite deadline. Snapshot includes events accepted before creation; CDC follows later commits. The ten-second configured interval is not a replication-latency guarantee.

Before relying on the table, inspect databases, tables, columns/comments, keys, skipping indexes, bounded sample rows and the execution plan. For example:

```sh
curl --max-time 20 --config .deployment/ch-admin.conf \
  --data-binary 'SHOW CREATE TABLE default.cdc_shipment_events'
curl --max-time 20 --config .deployment/ch-admin.conf \
  --data-binary "SELECT name,type FROM system.columns WHERE database='default' AND table='cdc_shipment_events' ORDER BY position LIMIT 30 FORMAT JSON"
curl --max-time 20 --config .deployment/ch-admin.conf \
  --data-binary 'GRANT SELECT ON default.cdc_shipment_events TO shipments_reports'
curl -sS --fail-with-body -H "Authorization: Bearer $TOKEN_A" http://127.0.0.1:3000/reports
```

The verified destination is `SharedReplacingMergeTree(...,_peerdb_version)` with ordering `(account_id,event_day,event_id)`, UUID identity, Date32 day, Int64 duration and nullable DateTime64 dispatch time. ClickPipes owns this versioned destination. Reports query `FINAL` and `_peerdb_is_deleted=0` to handle [replayed versions and tombstones](https://clickhouse.com/docs/integrations/clickpipes/postgres/deduplication). No forced `OPTIMIZE FINAL`, partitioning or naive incremental sum materialized view over raw CDC versions is needed.

Reports default to seven UTC days and accept only a range within the last 31 days including today. One account × 31 days × two service levels × three accepted target states bounds output to 186 groups. Each row contains event count, delivered count, total duration and maximum duration. All 64-bit aggregates are strings using explicit `toString`; JSON consumers cannot silently lose integer precision. No dispatch/delivery join is needed because the terminal event contains its facts.

One shared [official ClickHouse Node.js client](https://clickhouse.com/docs/integrations/language-clients/js/index) uses the configured HTTPS URL directly and closes on Nest shutdown. Typed placeholders and `query_params` bind account and dates. Interpolating caller input into SQL would introduce an SQL injection risk. Client settings are defaults and can be overridden per request; each report explicitly applies five-second execution, one-million-row / 100 MB scan and 186-result-row limits. The pool has two connections, ten-second request timeout and a 15-second abort signal. These layered limits do not promise an overall request duration. Bounded `JSONEachRow` results are consumed and closed. The app never inserts into ClickHouse.

Missing or unavailable analytics cannot reject a valid transition. Report responses label `consistency: "eventual"` and `operationalAuthority: "postgres"`; operational state/history always come from Postgres.

## Cloud acceptance checks

The manual tests mutate the seeded fixture and require private setup credentials. They do not run in CI. To reproduce the recorded suite, start from a fresh seed, use `node test/cloud-check.mjs snapshot` **instead of** the sample transition commands, then create the pipe and grant SELECT. In a dedicated test shell:

```sh
source .deployment/app.env
source .deployment/test-secrets.env
export TEST_MIGRATOR_PASSWORD="$SHIPMENTS_MIGRATOR_PASSWORD"
export TEST_CDC_PASSWORD="$SHIPMENTS_CDC_PASSWORD"
export TEST_CH_ADMIN_PASSWORD=$(jq -er .password .deployment/clickhouse-create.json)
openssl req -x509 -newkey rsa:2048 -nodes -keyout .deployment/wrong-ca.key \
  -out .deployment/wrong-ca.pem -days 1 -subj /CN=untrusted-shipment-test
export TEST_WRONG_CA="$PWD/.deployment/wrong-ca.pem"
node test/cloud-check.mjs snapshot # Run this once before pipe creation.
node test/cloud-check.mjs core
node test/security-check.mjs
node test/cloud-check.mjs equality
node test/pipeline-check.mjs reader
node test/process-restart.mjs
```

The fixture asserts one advance from two competing transitions, one event from ten simultaneous matching requests, retained/mismatched retries, uppercase UUID replay, account isolation, pagination/input/body bounds, and rollback after a forced event-insert failure. TLS and role tests prove accepted verified connections and denied untrusted CA, event mutation, DDL, cross-account FK and null dispatch timestamp. The restart test uses a separate port, confirms the old PID is gone and checks the child's environment before starting its replacement. Administrator test credentials never enter the application child.

For pipeline delay/outage and tombstone checks:

```sh
clickhousectl cloud clickpipe stop "$CH_ID" "$PIPE_ID" --org-id "$ORG_ID"
# Poll get until Paused before accepting the delayed fixture.
node test/pipeline-check.mjs lag
node test/pipeline-check.mjs outage
clickhousectl cloud clickpipe start "$CH_ID" "$PIPE_ID" --org-id "$ORG_ID"
# Poll get until Running; equality waits at most 180 seconds per account.
node test/cloud-check.mjs equality
node test/pipeline-check.mjs tombstone
node test/cloud-check.mjs equality
```

Outage is a controlled revocation of reporting SELECT: both slots fail with 503 while a PG transition succeeds, then both recover on the same client. The privileged tombstone test temporarily deletes and restores the exact fixture event through the owner role. It verifies the generated delete version and live-row exclusion; normal runtime event deletion remains prohibited. Final reports must equal current PG counts and duration aggregates for each account, including restoration. This is fixture maintenance evidence, not an application deletion feature.

Verified on 2 October 2026 against PostgreSQL 18.6 and analytical ClickHouse 26.6.1.2191: clean migrations/reversal/seed, four unit controls, HTTP races and rollback, restricted roles/TLS, initial snapshot and subsequent CDC, paused and unavailable analytics, recovered reports, exact aggregate equality and a genuine runtime-only process restart. Private raw logs and resource receipts are retained outside the repository. No scale or replication-latency guarantee follows from these small checks.

## Cleanup

Stop the API first. Delete your ClickPipe before its source/destination services; confirm each ID is absent from the corresponding list. A running analytical service requires `--force` to stop, poll and delete; Postgres deletion has no such flag.

```sh
clickhousectl cloud clickpipe delete "$CH_ID" "$PIPE_ID" --org-id "$ORG_ID"
# Remove any separately inventoried Query API credentials/endpoints, if created.
clickhousectl cloud postgres delete "$PG_ID" --org-id "$ORG_ID"
clickhousectl cloud service delete "$CH_ID" --org-id "$ORG_ID" --force
clickhousectl cloud postgres list --org-id "$ORG_ID" --json
clickhousectl cloud service list --org-id "$ORG_ID" --json
```

If keeping PG for other work, remove this fixture only with its saved admin credentials, after deleting its ClickPipe:

```sh
source .deployment/app.env
PGUSER=$(jq -er .username .deployment/postgres-create.json) \
  PGPASSWORD=$(jq -er .password .deployment/postgres-create.json) PGSSLMODE=verify-full \
  psql -X -v ON_ERROR_STOP=1 \
  -c 'DROP PUBLICATION shipments_events_clickpipe; DROP SCHEMA shipments CASCADE; DROP ROLE shipments_app, shipments_cdc, shipments_migrator, shipments_owner;'
```

Review role dependencies before adapting cleanup to a shared database. Never delete an unrelated service or the organization's API credential. See the [ClickHouse Managed Postgres overview](https://clickhouse.com/docs/products/managed-postgres/overview) for service context.
