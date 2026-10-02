# Inventory Transfers

A small Dart and Shelf JSON API moves synthetic stock between warehouses within one organization. A retained request UUID makes a matching retry return the original immutable transfer. Balances are read separately because they may have changed since that transfer.

This example uses ClickHouse Managed Postgres (public beta) in ClickHouse Cloud. It demonstrates stock movement, not purchasing, shipping, payments or reconciliation with physical inventory. Two environment bearer tokens represent trusted organization operators. This is a loopback workbench, not a public identity system; a Flutter/mobile client must never contain database credentials or these shared tokens.

Tested on 2 October 2026 with Dart 3.13.5 on Linux ARM64, Shelf 1.4.2, shelf_router 1.1.4, postgres 3.5.18 and PostgreSQL 18.6. `pubspec.lock` fixes transitive packages.

## How a transfer commits

`Transfers.submit()` runs every query on the `Pool.runTx` callback's transaction session:

1. Insert the organization/request UUID with `ON CONFLICT DO NOTHING RETURNING`.
2. For a retained key, read the committed transfer in a fresh READ COMMITTED statement. Matching source/destination/SKU/units return it; changed payload returns 409. UUID case is normalized.
3. For a new key, lock both existing balance rows in warehouse order with `FOR NO KEY UPDATE`, check source stock and destination capacity, then debit and credit. The transfer and both writes commit together.

The earlier insert's foreign keys acquire KEY SHARE locks on balances. Quantity-only `NO KEY UPDATE` locks are compatible with those checks while serializing quantity changes. Stronger `FOR UPDATE` upgrades can cause deadlocks between opposite-direction inserts. Both directions acquire the same pair in the same order. Exceptions escape the callback so the driver rolls back; the app never catches a uniqueness error and continues an aborted transaction.

If a connection fails while returning a commit response, its outcome may be unknown. Retry the same retained request ID rather than inventing another one. This is a stored-record retry protocol, not a claim about exactly-once physical effects.

## Create your Cloud fixture

Cloud services incur charges until deleted. Use a dedicated service; the reset script destroys this example's schema/roles. See the [Managed Postgres quickstart](https://clickhouse.com/docs/products/managed-postgres/quickstart).

```sh
umask 077
# Use an existing private directory outside the checkout.
export ORG_ID=your-clickhouse-organization-id
clickhousectl cloud postgres create \
  --org-id "$ORG_ID" --name inventory-transfers-demo \
  --provider aws --region us-east-1 --size c6gd.large \
  --pg-version 18 --ha-type none --json > /private/path/create.json
```

Store the returned ID, hostname, username and one-time password privately. Check the current available size/region for your organization; this modest shape was supported by the tested service. Wait until `state` is `running`:

```sh
export PG_ID=your-created-service-id
clickhousectl cloud postgres get "$PG_ID" --org-id "$ORG_ID"
clickhousectl cloud postgres certs get "$PG_ID" --org-id "$ORG_ID" \
  --output /private/path/ca.pem
```

Use `--output` to get a PEM file: the CLI automatically returns JSON to coding agents on stdout. The app creates a `SecurityContext(withTrustedRoots: false)` from this official CA and uses `SslMode.verifyFull`. In this driver `SslMode.require` ignores certificate errors and must not replace verification. The tested official bundle worked unchanged. Fetch a fresh certificate after Cloud certificate rotation.

## Native setup

Install stable Dart 3.13.5 for your Linux architecture and PostgreSQL's `psql` client. For the tested ARM64 VM:

```sh
sudo apt-get update
sudo apt-get install -y curl ca-certificates unzip postgresql-client
curl -fsSLO https://storage.googleapis.com/dart-archive/channels/stable/release/3.13.5/sdk/dartsdk-linux-arm64-release.zip
curl -fsSLO https://storage.googleapis.com/dart-archive/channels/stable/release/3.13.5/sdk/dartsdk-linux-arm64-release.zip.sha256sum
sha256sum -c dartsdk-linux-arm64-release.zip.sha256sum
unzip -q dartsdk-linux-arm64-release.zip
export PATH="$PWD/dart-sdk/bin:$PATH"
cd /path/to/examples/applications/inventory-transfers
dart pub get --enforce-lockfile
```

Copy `.env.example` to a private file outside the checkout, fill in the Cloud fields and separate role passwords, and generate two distinct 32–128 character ASCII bearer tokens. Do not commit that file or certificates. `PGPASSWORD` holds the runtime password; `MIGRATION_PASSWORD` is separate. `ADMIN_USER`/`ADMIN_PASSWORD` come from the Cloud create response. Export the fields before calling child processes:

```sh
set -a
source /private/path/setup.env
set +a
export PGSSLMODE=verify-full
APP_PASSWORD=$PGPASSWORD
export PGUSER=$ADMIN_USER PGPASSWORD=$ADMIN_PASSWORD
psql -X -v MIGRATION_PASSWORD="$MIGRATION_PASSWORD" -v APP_PASSWORD="$APP_PASSWORD" \
  -f sql/bootstrap.sql
export PGUSER=transfers_migration PGPASSWORD=$MIGRATION_PASSWORD
psql -X -f sql/migrate.sql
psql -X -f sql/grants.sql
psql -X -f sql/seed.sql
```

Bootstrap creates the schema and roles and revokes PUBLIC database CREATE/TEMP and public-schema CREATE on this dedicated fixture. The migration owner runs explicit versioned SQL under an advisory lock; migration and seed can be repeated. Seed inserts all warehouse/SKU combinations without resetting existing quantities. No startup migrations or automatic DDL run in the server.

The runtime can SELECT balances/transfers, INSERT transfers, use the identity sequence, and UPDATE only balance quantities. It cannot edit/delete transfers, change balance keys, create tables/schema/temp tables, or read migration history. Composite foreign keys keep organization/SKU/endpoints together; CHECKs enforce distinct endpoints, positive bounded units and bounded nonnegative balances. The shared runtime credential remains trusted: direct quantity UPDATEs can bypass application conservation. The database is not an independently enforced ledger.

## Run and try the API

```sh
export PGUSER=transfers_app PGPASSWORD=$APP_PASSWORD
unset ADMIN_USER ADMIN_PASSWORD MIGRATION_PASSWORD
dart run bin/server.dart
```

The server binds `127.0.0.1:4000` by default; PORT can change that local port. It verifies connectivity at startup. SIGINT/SIGTERM stops the listener, finishes active work and closes the pool. Alternatively, build and run the native executable:

```sh
mkdir -p build
dart compile exe bin/server.dart -o build/inventory-transfers
./build/inventory-transfers
```

Create `/private/path/runtime.env` with only `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER=transfers_app`, its `PGPASSWORD`, `PGSSLROOTCERT`, `NORTH_TOKEN`, `SOUTH_TOKEN` and optional `PORT`. Copy the runtime values from your private setup file; exclude `ADMIN_USER`, `ADMIN_PASSWORD` and `MIGRATION_PASSWORD`. Keep both files mode 600 with `chmod 600 /private/path/setup.env /private/path/runtime.env`. In another runtime-only shell:

```sh
set -a; source /private/path/runtime.env; set +a
curl -sS http://127.0.0.1:4000/balances \
  -H "Authorization: Bearer $NORTH_TOKEN"
curl -sS http://127.0.0.1:4000/transfers \
  -H "Authorization: Bearer $NORTH_TOKEN" -H 'Content-Type: application/json' \
  --data '{"request_id":"aaaaaaaa-1234-4567-890a-123456789abc","source":"depot","destination":"studio","sku":"bolts","units":25}'
```

Repeat that exact payload for 200/replay; change units under its key for 409. New transfers return 201. Unknown organization-scoped balances return 404; insufficient stock and destination capacity return 409. Tokens select the organization on the server; an organization body field is rejected. `/health` is public and reports process readiness after startup.

| Route | Bounded behavior |
| --- | --- |
| GET `/balances?limit=25&after=depot%2Fbolts` | Warehouse/SKU ascending; tuple cursor matches that order |
| GET `/transfers?limit=25&before=123` | Numeric identity descending; IDs remain decimal strings |
| POST `/transfers` | Exactly five fields; UUID, ASCII keys and integer units 1–1,000,000 |

Both lists default to 25 and cap at 100. `next_after`/`next_before` contain the last row's cursor; an additional empty page finishes traversal. Identity sequences can have gaps from retries/rollbacks, and their order is allocation order, not commit chronology. Retained rows are not automatically deleted. Lists are live reads, not a snapshot across pages. Transfer ordering qualifies the numeric table column: an unqualified `id` would select the `id::text` output alias and sort lexically. A targeted real API regression creates 12 transfers and pages across the 9/10/11/12 boundary.

JSON bodies cap at 4 KiB, with a 3-second **inactivity** timeout between stream events. Authentication happens before reading the body; eight active requests are admitted and further requests return 503. Error responses close their HTTP connection to avoid reusing unread rejected body bytes. A client still streaming a rejected body may observe a disconnect rather than a JSON response; the acceptance helper sends an explicit Content-Length. The pool caps at 4 connections; postgres 3.5.18's 5-second connectTimeout covers pool wait plus remaining connection setup. Queries have 8-second client timeout, 5-second server statement timeout and 3-second lock timeout. Busy/transient or unknown-outcome errors use 503/retry_request_id. Tokens, passwords and query parameters are not logged.

## Checks

```sh
dart format --output=none --set-exit-if-changed bin lib test
dart analyze
dart test test/domain_test.dart test/http_test.dart
```

The three native checks cover numeric/identifier parsing and a real loopback HTTP preflight. For the destructive **dedicated Cloud fixture** acceptance, first reset using administrator credentials, then repeat the setup above. Restore private administrator/migration fields in the test shell; the application process launched by tests receives a runtime-only whitelist.

```sh
set -a; source /private/path/setup.env; set +a
export APP_PASSWORD=$PGPASSWORD PGSSLMODE=verify-full
export PGUSER=$ADMIN_USER PGPASSWORD=$ADMIN_PASSWORD
psql -X -f sql/cleanup.sql
# Run bootstrap, migration twice, grants and seed twice as above.
export PGUSER=transfers_app PGPASSWORD=$APP_PASSWORD
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj /CN=UnrelatedAcceptanceCA \
  -keyout /private/path/wrong-ca.key -out /private/path/wrong-ca.pem
export WRONG_CA=/private/path/wrong-ca.pem
export SERVER_EXECUTABLE=/private/path/transfers-server
export WORKER_EXECUTABLE=/private/path/transfers-worker
dart compile exe bin/server.dart -o "$SERVER_EXECUTABLE"
dart compile exe bin/worker.dart -o "$WORKER_EXECUTABLE"
RUN_CLOUD=true dart test test/cloud_test.dart --concurrency=1 --reporter=expanded
```

Cloud acceptance checks organization-scoped HTTP replay and invalid inputs, prefix-key pagination, native constraints/grant denials, owner-only credit-trigger rollback after debit, independent blocked workers, actual opposite-direction HTTP requests, competing withdrawals, capacity, certificate controls and original-process exit before durable restart/replay. Tests use owner-only balance resets between cases and controlled trigger/foreign-warehouse fixtures; these are test setup, not runtime permissions. TLS negatives assert the pinned driver's specific `BadCertificateException`: wrong CA and an IP target with mismatched certificate name receive the same real peer certificate, then the actual DNS endpoint verifies successfully. No verification bypass is used.

## Cleanup

Stop the app. Optional schema reset requires freshly restored administrator credentials, since runtime instructions unset them:

```sh
set -a; source /private/path/setup.env; set +a
export PGUSER=$ADMIN_USER PGPASSWORD=$ADMIN_PASSWORD PGSSLMODE=verify-full
psql -X -f sql/cleanup.sql
clickhousectl cloud postgres delete "$PG_ID" --org-id "$ORG_ID"
clickhousectl cloud postgres list --org-id "$ORG_ID"
```

Confirm your exact ID is absent. Cleanup does not restore PUBLIC privileges or provide a production downgrade.

Primary references: [Dart PostgreSQL client](https://pub.dev/packages/postgres), [pool transaction session](https://pub.dev/documentation/postgres/latest/postgres/Pool/runTx.html), [pool settings](https://pub.dev/documentation/postgres/latest/postgres/PoolSettings-class.html), [TLS modes](https://pub.dev/documentation/postgres/latest/postgres/SslMode.html), [Shelf](https://pub.dev/packages/shelf), [Dart native compilation](https://dart.dev/tools/dart-compile).
