# Kotlin usage meter

An authenticated Ktor API accepts integer usage against an account's daily quota. ClickHouse Managed Postgres (public beta) stores accounts, counters and accepted events. ClickPipes copies events to an analytical ClickHouse service; the official Java client reads daily and feature totals. All three services run in ClickHouse Cloud. This is a software quota example, not a billing system.

The API binds to localhost. A server-configured bearer token determines the account; clients cannot supply an account ID. `POST /usage` locks that account, checks a retained request ID, then updates its UTC daily counter and inserts an event in one Exposed transaction. A matching retry returns the original result, even after quota exhaustion or UTC midnight. A changed feature or units returns 409. The application never writes to ClickHouse.

## Behavior and limits

| Route | Result |
|---|---|
| `POST /usage` |201 for a newly accepted event,200 for a matching retained retry,409 for changed data,429 for exhausted quota |
| `GET /events/{requestId}` | Authenticated account's original acceptance result or 404 |
| `GET /quota` | Current UTC day's authoritative Postgres counter and remaining quota |
| `GET /reports?from=YYYY-MM-DD&to=YYYY-MM-DD` | Eventually consistent daily totals and feature breakdowns for that account |

Request IDs contain 1–64 ASCII letters, digits, `.`, `_` or `-`. Units are 1–1,000; features are `api`, `export`, `storage`. Bodies are limited to 4 KiB; unknown JSON fields are rejected. Seed accounts have quotas 100 and 50. The account/request-ID unique constraint spans all dates: IDs are retained with their events indefinitely in this example. Implement coordinated retention before treating this as a production service; deleting an event releases its retry protection.

Reports default to the last seven UTC days and permit only dates within the last 31 UTC days, including today. One account and three fixed features bound the result to 93 feature rows. Dates/account are query parameters, never SQL interpolation. Every successful report explicitly includes `consistency: "eventual"` and `quotaAuthority: "postgres"`. Missing pipeline data is not spare quota. The remaining amount on an acceptance response describes that acceptance, not the current counter.

The shared Postgres runtime role is trusted application code, not a database tenant boundary. HTTP authentication supplies account scope. It cannot update/delete events, perform DDL or access migration history, but it can insert events and update counters; `UPDATE(id)` on accounts permits row locking. Do not expose these credentials to clients. Tokens are not stored in the replicated table. Use a real identity provider and per-account access policy before public deployment.

A lost response can leave a committed event: retry the same ID and data to obtain the retained result, potentially 200 without ever observing 201. Temporary database/report failures return 503. Different accounts can progress concurrently; requests for one account serialize. This is deliberately a small example, with no throughput claim.

## Requirements and build

Use JDK 21, `psql`, Python 3, OpenSSL, curl, jq and [clickhousectl](https://clickhouse.com/docs/concepts/features/interfaces/cli). Configure the CLI's organization credentials without putting them in application runtime files. All commands below run from this directory in a Linux environment. Build/test dependency installation needs no database credentials:

```sh
./gradlew --no-daemon clean test installDist
```

The wrapper pins Gradle 9.8.0 with its distribution checksum. Dependency locks pin Kotlin 2.4.20, Ktor 3.6.0, Exposed 1.5.0, pgJDBC 42.7.13 and `client-v2` 0.10.0, plus transitive versions. Four unit tests run normally; two real Cloud tests are opt-in. SQL migrations are explicit files, rather than schema generation during startup. `Store.kt` uses Exposed's JDBC transactions on a five-worker IO dispatcher; the pool has five connections. Postgres connect/pool acquisition/statement/socket limits are 5/15/20/25 seconds. These are layer limits, not an HTTP response-time promise.

## Create the Cloud services

These resources incur charges. Use a dedicated test name, save receipts privately, and delete your resources after validation. The demonstrated small Postgres shape is `c6gd.large` in AWS `us-east-1`, PostgreSQL 18 without HA. Check current availability and cost before reusing it. The analytical service uses the CLI's current minimum 8 GiB per replica and two replicas for a new warehouse.

```sh
umask 077
mkdir -p .deployment
export ORG_ID='your-organization-id'
export DEV_EGRESS_IP='your-development-public-egress-ip'
clickhousectl cloud postgres create --org-id "$ORG_ID" \
  --name usage-meter-pg --provider aws --region us-east-1 \
  --size c6gd.large --pg-version 18 --ha-type none --json \
  > .deployment/postgres-create.json
export PG_ID=$(jq -er .id .deployment/postgres-create.json)
clickhousectl cloud service create --org-id "$ORG_ID" \
  --name usage-meter-analytics --provider aws --region us-east-1 \
  --min-replica-memory-gb 8 --max-replica-memory-gb 8 --num-replicas 2 \
  --idle-scaling false --ip-allow "$DEV_EGRESS_IP/32=usage-meter-dev" --json \
  > .deployment/clickhouse-create.json
export CH_ID=$(jq -er .service.id .deployment/clickhouse-create.json)
```

Poll `cloud postgres get "$PG_ID"` and `cloud service get "$CH_ID"` with `--org-id "$ORG_ID" --json` until both states are `running`; use a finite deadline (for example ten minutes). Do not continue on failure. The create receipts contain passwords that `get` does not return. Restrict the analytical endpoint allowlist to your development egress, and update it when that address changes. ClickPipes manages its destination connectivity. Keep source credentials restricted to publication replication.

```sh
clickhousectl cloud postgres certs get "$PG_ID" --org-id "$ORG_ID" \
  --output .deployment/postgres-ca.pem
export PGHOST=$(jq -er .hostname .deployment/postgres-create.json)
export PGPORT=5432 PGDATABASE=postgres PGSSLMODE=verify-full
export PGSSLROOTCERT="$PWD/.deployment/postgres-ca.pem"
export PGADMIN=$(jq -er .username .deployment/postgres-create.json)
export PGPASSWORD=$(jq -er .password .deployment/postgres-create.json)
export USAGE_MIGRATOR_PASSWORD="Aa1_$(openssl rand -hex 24)"
export USAGE_APP_PASSWORD="Aa1_$(openssl rand -hex 24)"
export USAGE_CDC_PASSWORD="Aa1_$(openssl rand -hex 24)"
psql -X -v ON_ERROR_STOP=1 -U "$PGADMIN" -f sql/bootstrap.sql
PGUSER=usage_migrator PGPASSWORD="$USAGE_MIGRATOR_PASSWORD" \
  psql -X -v ON_ERROR_STOP=1 -f sql/migrate.sql
PGUSER=usage_migrator PGPASSWORD="$USAGE_MIGRATOR_PASSWORD" \
  psql -X -v ON_ERROR_STOP=1 -f sql/seed.sql
psql -X -v ON_ERROR_STOP=1 -U "$PGADMIN" -f sql/publication.sql
```

Bootstrap creates a non-login owner, a migration login, an application login and a replication login. Migration 1 is recorded under an advisory lock; repeating migrate/seed is safe. `sql/revert.sql` drops application tables and their data; for a lifecycle check use it **before** accepting events/creating the pipe, then migrate/seed again. Bootstrap creates roles once. Publication setup runs with admin credentials and requires logical replication.

The source's NOT NULL unique index `(account_id,usage_day,event_id)` is its replica identity. This includes every [custom ClickPipes ordering column](https://clickhouse.com/docs/integrations/clickpipes/postgres/ordering-keys), so privileged deletion tombstones retain their full deduplication key. These columns are immutable in normal operation. Only `usage.events` belongs to the publication; accounts/counters/tokens are not replicated.

Create the analytical reporting user through the service's trusted HTTPS endpoint. Keep its password separate from the admin password:

```sh
export CLICKHOUSE_URL="https://$(jq -er '.service.endpoints[] | select(.protocol=="https") | .host' .deployment/clickhouse-create.json):$(jq -er '.service.endpoints[] | select(.protocol=="https") | .port' .deployment/clickhouse-create.json)"
export CH_REPORT_PASSWORD="Aa1_$(openssl rand -hex 24)"
printf 'url="%s/?max_execution_time=10&max_rows_to_read=1000000&max_bytes_to_read=100000000"\nuser="default:%s"\nfail-with-body\nsilent\nshow-error\n' \
  "$CLICKHOUSE_URL" "$(jq -er .password .deployment/clickhouse-create.json)" \
  > .deployment/ch-admin.conf
printf "CREATE USER usage_reports IDENTIFIED BY '%s' SETTINGS readonly=2, max_execution_time=5, max_rows_to_read=1000000, max_bytes_to_read=100000000, max_result_rows=93, result_overflow_mode='throw', max_threads=2;" \
  "$CH_REPORT_PASSWORD" > .deployment/report-user.sql
curl --config .deployment/ch-admin.conf --data-binary @.deployment/report-user.sql
export TOKEN_A=$(openssl rand -hex 32) TOKEN_B=$(openssl rand -hex 32)
export ACCOUNT_TOKENS=$(jq -cn --arg a "$TOKEN_A" --arg b "$TOKEN_B" \
  '{"00000000-0000-4000-8000-000000000001":$a,"00000000-0000-4000-8000-000000000002":$b}')
{
  printf 'export PGHOST=%q PGPORT=5432 PGDATABASE=postgres PGUSER=usage_app\n' "$PGHOST"
  printf 'export PGPASSWORD=%q PGSSLROOTCERT=%q\n' "$USAGE_APP_PASSWORD" "$PGSSLROOTCERT"
  printf 'export CLICKHOUSE_URL=%q CLICKHOUSE_USER=usage_reports CLICKHOUSE_PASSWORD=%q\n' "$CLICKHOUSE_URL" "$CH_REPORT_PASSWORD"
  printf 'export ACCOUNT_TOKENS=%q\n' "$ACCOUNT_TOKENS"
} > .deployment/app.env
{
  printf 'export USAGE_MIGRATOR_PASSWORD=%q\n' "$USAGE_MIGRATOR_PASSWORD"
  printf 'export USAGE_CDC_PASSWORD=%q\n' "$USAGE_CDC_PASSWORD"
} > .deployment/test-secrets.env
```

Never use `default` as the application client. `readonly=2` allows bounded query settings but prohibits writes; the following table-only grant is installed after the pipe creates its table. These direct HTTPS administration commands create no Cloud Query API credential. If instead using `cloud service query`, inventory and later remove any automatically created Query API credentials/endpoints; preserve your pre-existing organization API key.

## Run and create snapshot fixtures

Start a **fresh shell**, then load only runtime values:

```sh
source .deployment/app.env
PORT=3300 bash scripts/start-runtime.sh
export TOKEN_A=$(jq -er '."00000000-0000-4000-8000-000000000001"' <<< "$ACCOUNT_TOKENS")
export TOKEN_B=$(jq -er '."00000000-0000-4000-8000-000000000002"' <<< "$ACCOUNT_TOKENS")
curl -sS --fail-with-body -H "Authorization: Bearer $TOKEN_A" -H 'Content-Type: application/json' \
  -d '{"requestId":"snapshot-api","feature":"api","units":5}' http://127.0.0.1:3300/usage
curl -sS --fail-with-body -H "Authorization: Bearer $TOKEN_A" -H 'Content-Type: application/json' \
  -d '{"requestId":"snapshot-export","feature":"export","units":3}' http://127.0.0.1:3300/usage
curl -sS --fail-with-body -H "Authorization: Bearer $TOKEN_B" -H 'Content-Type: application/json' \
  -d '{"requestId":"snapshot-b","feature":"api","units":4}' http://127.0.0.1:3300/usage
```

The helper whitelists only runtime fields for the child process, excluding setup credentials even if the invoking shell still has them. It checks authenticated quota readiness with a 90-second deadline. The JVM binds to localhost. Postgres verifies the downloaded CA and hostname with pgJDBC `verify-full`; ClickHouse uses normal trusted HTTPS, with no permissive trust manager. Logs/errors omit credentials and database connection strings.

Before creating the pipe, run the optional real Cloud controls. Generate a different CA and pass its path; these tests do not use a local Postgres substitute:

```sh
source .deployment/app.env
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=wrong-ca \
  -keyout .deployment/wrong-ca.key -out .deployment/wrong-ca.pem
RUN_CLOUD_TESTS=1 TEST_WRONG_CA="$PWD/.deployment/wrong-ca.pem" \
  ./gradlew --no-daemon test --rerun-tasks
```

This runs four unit tests plus verified TLS/wrong-CA/wrong-hostname and fixed-clock UTC-midnight retry tests. The clock test adds one event to accountB's preceding-day counter while leaving its current-day counter unchanged.

## Create ClickPipes and read reports

In the original **setup shell**, whose `PGHOST`, IDs and replication password are still set (or explicitly restore those values from the private receipts/test-secrets file):

```sh
clickhousectl cloud clickpipe create postgres "$CH_ID" --org-id "$ORG_ID" \
  --name usage-meter-events --host "$PGHOST" --port 5432 --pg-database postgres \
  --username usage_cdc --password "$USAGE_CDC_PASSWORD" \
  --ca-certificate .deployment/postgres-ca.pem --publication-name usage_events_clickpipe \
  --replication-mode cdc --sync-interval-seconds 10 --pull-batch-size 10000 \
  --initial-load-parallelism 1 --snapshot-parallel-tables 1 --delete-on-merge false \
  --table-mapping-json "$(cat infra/clickpipe-events.json)" --json \
  > .deployment/clickpipe-create.json
export PIPE_ID=$(jq -er .id .deployment/clickpipe-create.json)
clickhousectl cloud clickpipe get "$CH_ID" "$PIPE_ID" --org-id "$ORG_ID" --json
```

Wait with a finite deadline for `Running` and for `default.cdc_usage_events` to exist. If the analytical service was idled, wake it and wait for `running` before pipe creation. The mapping asks ClickPipes to create a ReplacingMergeTree destination, no partition and custom `(account_id,usage_day,event_id)` sorting. Do not manually create or modify this managed table. Inspect databases/tables, columns/comments, `SHOW CREATE TABLE`, indices, a limited sample and `EXPLAIN` before relying on its layout:

```sh
curl --config .deployment/ch-admin.conf --data-binary 'SHOW CREATE TABLE default.cdc_usage_events'
curl --config .deployment/ch-admin.conf --data-binary \
  'GRANT SELECT ON default.cdc_usage_events TO usage_reports'
```

The validated Cloud mapping produced `SharedReplacingMergeTree(...,_peerdb_version)` with UUIDs, `Date32`, `Int16` units, `Int32` remaining and `DateTime64(6)` timestamps. Feature is `String`: source/API checks bound it to three values; this example leaves the managed mapping intact rather than altering it to Enum/LowCardinality. There is no lifecycle requirement for partitioning and no materialized view over the CDC version stream.

`Analytics.kt` applies `FINAL` and filters `_peerdb_is_deleted=0` **before** aggregation, following [ClickPipes deduplication guidance](https://clickhouse.com/docs/integrations/clickpipes/postgres/deduplication). Background merges are not assumed complete. No `OPTIMIZE FINAL` is issued. Reports filter on the ordering prefix and have 5-second execution,1 million scanned rows,100 MB scanned bytes and 93 result-row caps; cap violations fail instead of returning partial totals.

The synchronous Java client runs on its own two-worker IO dispatcher, uses two connections, zero automatic retries, 5-second connect/pool-acquisition and 10-second socket limits. The additional 15-second Future wait is not an end-to-end request deadline. Slow/unavailable analytics returns 503 without being consulted for quota. The startup check consults Postgres accounts; it does not require reports to be ready.

```sh
# Runtime shell
curl -sS --fail-with-body -H "Authorization: Bearer $TOKEN_A" http://127.0.0.1:3300/quota
curl -sS --fail-with-body -H "Authorization: Bearer $TOKEN_A" http://127.0.0.1:3300/reports
source .deployment/test-secrets.env  # Test runner only; never added to app.env.
python3 scripts/cloud-core.py
REPORT_EVIDENCE=.deployment/converged.json python3 scripts/cloud-convergence.py
bash scripts/process-restart.sh
```

Run `cloud-core.py` once on the fresh snapshot fixture (Aused 8/Bused 4). Twelve clients retry 503 only with the original ID/data and a bounded retry deadline; output distinguishes clients from actual attempts. It asserts one retained event/debit, changed retry 409, exact quota 100 with nine accepted ten-unit requests and three denied, exhausted matching retry 200, cross-account 404, auth/body/date controls, role denials and rollback after a counter mutation. Its temporary owner-created trigger forces event insertion to fail, then is removed in `finally`. The convergence check compares exact day/feature sums **and counts** to Postgres, with a 180-second polling deadline. Stop new writes while performing that fixed expected-snapshot comparison.

To demonstrate lag, use `clickpipe stop "$CH_ID" "$PIPE_ID" --org-id "$ORG_ID"`, wait for `Paused`, accept additional usage for account B, and observe that `/quota` advances while `/reports` retains its earlier totals. Resume with `clickpipe start`, wait for `Running`, then repeat convergence. The supplied `cloud-lag.py` makes this check explicit. Run `python3 scripts/cloud-lag.py prepare` after convergence, pause/wait, then run `python3 scripts/cloud-lag.py paused`; the latter accepts six units for account B and checks unchanged reports. To test an analytical access outage, temporarily use the admin HTTPS config to `REVOKE SELECT ON default.cdc_usage_events FROM usage_reports`, run `python3 scripts/cloud-lag.py outage`, then restore `GRANT SELECT ON default.cdc_usage_events TO usage_reports` even if the test fails. `python3 scripts/cloud-lag.py recover` checks both report capacity slots in the same process. Resume the pipe and run convergence again. These controls require the dedicated fixture; they change its accepted-event totals.

Ten seconds is a configured sync interval, not an ingestion-latency promise. Privileged source maintenance and `clickpipe resync` are separate controls; they are not normal runtime event mutations.

## Cleanup

Stop each locally started process using its `.deployment/server-PORT.pid`. In the setup shell restore resource IDs from receipts if needed. Delete the pipe before databases and verify each ID is absent from its corresponding list. Remove only ancillary Query API resources created by your own optional administration route; none are created by the direct HTTPS procedure above.

```sh
clickhousectl cloud clickpipe delete "$CH_ID" "$PIPE_ID" --org-id "$ORG_ID"
clickhousectl cloud clickpipe list "$CH_ID" --org-id "$ORG_ID" --json
clickhousectl cloud postgres delete "$PG_ID" --org-id "$ORG_ID"
clickhousectl cloud service delete "$CH_ID" --org-id "$ORG_ID" --force
clickhousectl cloud postgres list --org-id "$ORG_ID" --json
clickhousectl cloud service list --org-id "$ORG_ID" --json
```

If retaining the databases but removing this fixture, first delete the pipe, then use the admin receipt rather than runtime credentials:

```sh
source .deployment/app.env
export PGSSLMODE=verify-full
export PGUSER=$(jq -er .username .deployment/postgres-create.json)
export PGPASSWORD=$(jq -er .password .deployment/postgres-create.json)
psql -X -v ON_ERROR_STOP=1 -c 'DROP PUBLICATION usage_events_clickpipe; DROP SCHEMA usage CASCADE; DROP ROLE usage_app, usage_cdc, usage_migrator; DROP ROLE usage_owner;'
curl --config .deployment/ch-admin.conf --data-binary 'DROP USER usage_reports'
curl --config .deployment/ch-admin.conf --data-binary 'DROP TABLE IF EXISTS default.cdc_usage_events'
```

Remove private receipts/runtime files after your own retention needs are met. See [ClickHouse Managed Postgres documentation](https://clickhouse.com/docs/products/managed-postgres/overview), [Ktor authentication](https://ktor.io/docs/server-auth.html), [Exposed transactions](https://www.jetbrains.com/help/exposed/transactions.html), [pgJDBC TLS](https://jdbc.postgresql.org/documentation/ssl/) and the [Java client](https://clickhouse.com/docs/integrations/language-clients/java/client).
