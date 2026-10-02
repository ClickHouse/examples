# Redirect Links

A small Rust/Actix Web management API creates and disables operator-scoped redirect links on [ClickHouse Managed Postgres](https://clickhouse.com/docs/products/managed-postgres/overview). Public GET/HEAD lookups return a temporary redirect only while a link is enabled and unexpired. The service never fetches, previews or checks the reputation of submitted destinations.

This example deliberately integrates Diesel's synchronous PostgreSQL connection and typed query builder with Actix's blocking thread pool. It has no click analytics, external messaging, billing or browser visits to third-party sites.

## Data and transaction model

Two seeded operator accounts, north and south, have distinct configured bearer tokens. The server derives account identity from the token; owner fields are rejected. Shared tokens are trusted operator credentials, not end-user accounts. The shared runtime database role can read both accounts' data directly; API filters enforce operator boundaries, without per-user RLS.

A link has a globally unique canonical slug, immutable destination/expiry, a revision and an optional disabled timestamp. Creation locks its account row, checks the 20-link cap, increments its counter and inserts the link on the same connection in one Diesel transaction. A slug collision rolls back the counter and returns 409. Creation has **no retained request key**: repeating a successful POST returns a slug conflict, even with the same destination. After a lost response, inspect the owner's list before deciding what to do next.

Disable locks the owned link and compares the revision the operator saw. Enabled links move from revision 1 to 2. A repeated disable carrying 1 or the current disabled revision 2 returns the existing state; other positive revisions conflict. There is no re-enable or destination edit operation. Disabled and expired rows still consume the account's cap, keeping the teaching fixture finite.

The runtime can SELECT accounts/links, INSERT links, use the identity sequence, UPDATE only account counters and UPDATE only disabled_at/revision. It cannot mutate owners/slugs/destinations/expiry, delete rows, read migration history, or create application/schema/temp objects. Constraints enforce global slug uniqueness/canonical grammar, account FK, positive identity, bounded counters, destination size/basic scheme and coherent revision/disabled state. Direct trusted runtime SQL can insert without updating the counter or change permitted metadata; the complete cap/counter/one-way-disable protocol depends on cooperating application code.

## Blocking-work lifetime

Pool checkout and every SQL operation run inside `web::block`, including the full multi-statement transaction. Four owned admission permits are shared across both HTTP workers. A permit moves into the blocking closure before checkout and remains there until actual work finishes. Dropping an awaiting HTTP future doesn't release capacity while its synchronous SQL continues; an abandoned operation can still commit.

The r2d2 pool has four connections, zero minimum idle connections, a two-second checkout timeout, one-minute idle timeout and five-minute maximum lifetime. New libpq connections use `connect_timeout=5`, `sslmode=verify-full` and an explicit CA/hostname. Statement/lock/idle-transaction timeouts are four/two/six seconds. Connection establishment runs in r2d2's bounded pool management; checkout can time out while a background connection attempt completes. These are separate controls, not a total HTTP deadline.

Actix has two HTTP workers, at most four blocking threads per worker, 32 connections **per worker**, a five-second initial-request timeout, five-second keepalive and ten-second graceful shutdown timeout. JSON bodies cap at 4 KiB. Lists return at most 20 rows with destinations bounded to 2 KiB each. Multiple server processes each have their own local limits; the database account lock coordinates their creation transactions.

## Native setup and locked build

Tested on 2 October 2026: Ubuntu 24.04 ARM64, Rust/Cargo 1.99.0, Actix Web 4.15.0, Diesel 2.3.13, r2d2 0.8.10, Tokio 1.53.1, URL 2.5.8 and libpq 16.15. Cargo.lock records 190 package entries; rust-toolchain.toml pins the compiler and components. All builds/dependencies stay in the native Linux filesystem.

```sh
sudo apt-get update
sudo apt-get install -y build-essential libpq-dev postgresql-client pkg-config \
  libssl-dev curl ca-certificates git
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o /tmp/rustup-init.sh
sh /tmp/rustup-init.sh -y --profile minimal --default-toolchain 1.99.0
source "$HOME/.cargo/env"
cd /path/to/examples/applications/redirect-links
cargo fetch --locked
cargo fmt --check
cargo test --locked
cargo clippy --locked --all-targets -- -D warnings
cargo build --release --locked
python3 test/preflight.py "$PWD/target/release/redirect-links"
```

Three local tests cover canonical inputs/numeric/calendar bounds and a real blocked-closure cancellation/admission control. The separate compiled HTTP preflight runs only `/health` without a database and waits for SIGTERM exit. The Cloud cancellation test is explicitly ignored by default. CI runs these local checks without Cloud credentials.

## Create a dedicated Cloud fixture

Use an authenticated [clickhousectl](https://github.com/ClickHouse/clickhousectl) CLI. Creating a service starts billing; delete it after testing. Check current supported region/shape for your organization. The tested modest shape was:

```sh
umask 077
export ORG_ID=your-clickhouse-organization-id
clickhousectl cloud postgres create --org-id "$ORG_ID" \
  --name redirect-links-demo --provider aws --region us-east-1 \
  --size c6gd.large --pg-version 18 --ha-type none --json > /private/path/create.json
export PG_ID=your-created-service-id
clickhousectl cloud postgres get "$PG_ID" --org-id "$ORG_ID"
# Repeat get until state is running, then fetch the official PEM:
clickhousectl cloud postgres certs get "$PG_ID" --org-id "$ORG_ID" \
  --output /private/path/ca.pem
```

Store the returned service ID, hostname, username and one-time password privately. `--output` writes PEM even when coding-agent CLI stdout is JSON. The actual Diesel factory uses libpq certificate **and** hostname verification with the full official bundle. Refresh that official bundle after certificate rotation; don't weaken verification to `require`.

## Explicit migration and seed

Copy `.env.example` to a private mode-600 setup.env outside the checkout. Fill in Cloud connection fields, administrator credentials, a separate migration password, the runtime password in PGPASSWORD, and two distinct 32–128 character printable ASCII tokens without spaces. Quote shell-sensitive values. Export fields before calling child processes:

```sh
set -a; source /private/path/setup.env; set +a
export PGSSLMODE=verify-full
APP_PASSWORD=$PGPASSWORD
export PGUSER=$ADMIN_USER PGPASSWORD=$ADMIN_PASSWORD
psql -X -v MIGRATION_PASSWORD="$MIGRATION_PASSWORD" -v APP_PASSWORD="$APP_PASSWORD" \
  -f sql/bootstrap.sql
export PGUSER=redirects_migration PGPASSWORD=$MIGRATION_PASSWORD
./target/release/redirect-links migrate
psql -X -f sql/grants.sql
psql -X -f sql/seed.sql
```

Bootstrap creates the schema/roles and revokes PUBLIC database CREATE/TEMP and public-schema CREATE on this dedicated fixture. The schema owner needs no database CREATE. `migrate` uses the same reviewed SQL embedded in the binary, version history and an advisory transaction lock; repeat it safely. Seed creates north/south accounts without resetting existing counters. Normal server startup never migrates or synchronizes schema. The runtime role cannot run the migration command.

## Run and use the API

```sh
export PGUSER=redirects_app PGPASSWORD=$APP_PASSWORD
unset ADMIN_USER ADMIN_PASSWORD MIGRATION_PASSWORD
./target/release/redirect-links
```

The listener binds `127.0.0.1:4000`; PORT can change that local port. Startup verifies a runtime connection before opening the listener. `/health` reports process readiness, without a continuous database probe. SIGTERM requests graceful shutdown; the restart acceptance waits for the original process to exit before replacing it.

Create a private mode-600 runtime.env with only PGHOST, PGPORT, PGDATABASE, PGUSER=redirects_app, its PGPASSWORD, PGSSLROOTCERT, NORTH_TOKEN, SOUTH_TOKEN and optional PORT. In a second shell:

```sh
set -a; source /private/path/runtime.env; set +a
curl -sS http://127.0.0.1:4000/links \
  -H "Authorization: Bearer $NORTH_TOKEN" -H 'Content-Type: application/json' \
  --data '{"slug":"Docs-Guide","destination":"https://clickhouse.com/docs/products/managed-postgres/overview"}'
curl -sS 'http://127.0.0.1:4000/links?limit=10' -H "Authorization: Bearer $NORTH_TOKEN"
# Inspect redirect headers without following the destination:
curl -sS -I http://127.0.0.1:4000/r/docs-guide
curl -sS http://127.0.0.1:4000/links/docs-guide/disable \
  -H "Authorization: Bearer $NORTH_TOKEN" -H 'Content-Type: application/json' \
  --data '{"revision":"1"}'
```

| Route | Behavior |
| --- | --- |
| POST `/links` | 201 on creation, 409 on canonical slug collision/account full |
| GET `/links?limit=10&before=123` | Owner-scoped numeric identity descending; limit 1–20 |
| POST `/links/{slug}/disable` | 200 on revision-matched disable/repeat; 404 foreign/missing, 409 conflicting revision |
| GET/HEAD `/r/{slug}` | 307 plus canonical Location when active; 404 missing/invalid/disabled/expired; no-store |

Slugs are 3–40 ASCII letters/digits with internal hyphens, normalized to lowercase. health/links/admin/api/static are reserved. Destinations use the URL parser, require explicit HTTP(S) authority/host, reject userinfo/control characters/surrounding whitespace and cap the canonical serialized URL at 2048 bytes. Expiry is null/omitted or RFC3339, normalized to UTC, years 1970–2100 with at most microsecond precision and no leap second. Past expiry is allowed and resolves to 404. Database `clock_timestamp()` determines expiry at lookup; an already authorized response cannot be retracted by a later disable.

IDs/revisions are decimal strings. An initial page has no cursor predicate, so even INT64_MAX remains visible. Subsequent `before` is a positive signed bigint string of at most 19 digits. `next_before` contains the last row's ID; traverse until an empty page. Numeric ordering stays in Diesel/SQL while string serialization happens in Rust. Identity allocation order is not commit chronology; gaps are normal, and pages are live reads rather than a snapshot.

## Dedicated Cloud acceptance

Tests are destructive fixtures, not production checks. Stop the server, restore private setup credentials and run cleanup, then repeat bootstrap/migrate twice/grants/seed twice above. The compiled HTTP child receives only runtime fields; independent owner/admin controls stay in the test process.

```sh
set -a; source /private/path/setup.env; set +a
export PGSSLMODE=verify-full
APP_PASSWORD=$PGPASSWORD
export PGUSER=$ADMIN_USER PGPASSWORD=$ADMIN_PASSWORD
psql -X -f sql/cleanup.sql
# Repeat documented bootstrap, migrate twice, grants and seed twice.
export PGUSER=redirects_app PGPASSWORD=$APP_PASSWORD
export REDIRECTS_EXECUTABLE="$PWD/target/release/redirect-links"
export EVIDENCE_DIR=/private/path/acceptance
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj /CN=UnrelatedAcceptanceCA \
  -keyout /private/path/wrong-ca.key -out /private/path/wrong-ca.pem
export WRONG_CA=/private/path/wrong-ca.pem
cargo test --locked --test cancellation_cloud -- --ignored --nocapture
python3 test/cloud.py
```

The separate native Cloud test observes four actual blocked Diesel connections, aborts one awaiting task, verifies admission remains exhausted, then observes all four writes committed and later admission restored. It removes its rows/counters before HTTP cases. The HTTP helper never follows redirects. Cases cover canonical collisions/ownership, actual blocked HTTP transactions with independent progress, account-cap contention, counter rollback after insert failure, actual deferred COMMIT failure, twelve real inserts across 99/100 plus an owner-controlled INT64_MAX row, expiry/disable/revisions, grants/constraints/trusted-role bypass, certificate-specific negatives with positive DNS control, and durable replay of reads after confirmed process exit/restart.

Held-lock HTTP checks first warm the actual pool for observable independent sessions; this test-only preparation leaves production connection, statement and lock limits unchanged.

Owner-only fixture triggers, sequence adjustment and maximum-ID/full-account rows accelerate specific boundaries; they do not change runtime grants or imply throughput. Raw certificate diagnostics remain private. The fixture reset is not a production downgrade.

## Cleanup

Stop the app. Optional schema destruction requires administrator fields restored after the runtime commands unset them:

```sh
set -a; source /private/path/setup.env; set +a
export PGUSER=$ADMIN_USER PGPASSWORD=$ADMIN_PASSWORD PGSSLMODE=verify-full
psql -X -f sql/cleanup.sql
clickhousectl cloud postgres delete "$PG_ID" --org-id "$ORG_ID"
clickhousectl cloud postgres list --org-id "$ORG_ID"
```

Confirm your exact ID is absent. PUBLIC revocations remain after schema cleanup.

Primary references: [Actix/Diesel integration](https://actix.rs/docs/databases/), [Actix 4.15 blocking API](https://docs.rs/actix-web/4.15.0/actix_web/web/fn.block.html), [Diesel transaction closure](https://docs.diesel.rs/2.3.x/diesel/connection/trait.Connection.html), [libpq verification and connection options](https://www.postgresql.org/docs/current/libpq-connect.html).
