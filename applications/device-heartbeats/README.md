# Device Heartbeats

A small C++20/Drogon API saves synthetic readings and advances each device's latest sequence in one transaction on [ClickHouse Managed Postgres (public beta)](https://clickhouse.com/docs/products/managed-postgres/overview). Project tokens select seeded devices; matching sample UUIDs replay retained results. This is an instructional ingestion protocol, without hardware integration or monitoring/alerting behavior.

## Transaction and trust model

A write locks the `(project, device)` parent, checks a retained UUID **before** checking the latest sequence or 200-sample cap, inserts history, and updates the parent's latest sequence/count. Every query uses the same Drogon transaction. A retained request replays only when sequence, integer reading and canonical optional observation time match. A different UUID must carry a strictly greater sequence. No history is silently pruned.

Drogon 1.9.13 queues COMMIT when its transaction is destroyed. The final SQL callback releases our transaction pointer, breaking the callback/state ownership cycle. Only the COMMIT callback can send 201/200. Rollback paths resolve HTTP independently because Drogon does not invoke that callback on rollback. Failed or uncertain commits return 503/`retry_sample_id`; retry the same UUID and payload to resolve the durable outcome.

Tokens are distinct 32–128 character printable ASCII secrets for trusted project operators. They are not individual device identities. The server derives the project; no project field is accepted in JSON. The shared runtime database role is also trusted: it can directly insert history or change permitted parent metadata, bypassing the application's monotonic-sequence, true-count and history-cap protocol. Grants deny history UPDATE/DELETE, key edits and DDL; constraints enforce UUID/sequence uniqueness, positive sequence, reading bounds, bounded parent counters and the composite device foreign key. They do not independently enforce consistency between history and parent metadata.

## Build on native Linux

Tested 2 October 2026 on Ubuntu 24.04 ARM64: GCC 13.3.0, CMake 3.28.3, Drogon 1.9.13, Trantor revision below, JsonCpp 1.9.5, OpenSSL 3.0.13 and libpq 16.15. PostgreSQL server was 18.6. Framework sources are pinned; distro packages provide native libraries. Build outside shared host mounts:

```sh
sudo apt-get update
sudo apt-get install -y build-essential cmake git pkg-config libjsoncpp-dev \
  libssl-dev libpq-dev uuid-dev zlib1g-dev libbrotli-dev postgresql-client \
  curl ca-certificates clang-format
git clone --branch v1.9.13 --depth 1 --recurse-submodules \
  https://github.com/drogonframework/drogon.git "$HOME/drogon-source"
test "$(git -C "$HOME/drogon-source" rev-parse HEAD)" = 4c5430757ea5451a7c38fbbef4b4bef7dbb47f2f
test "$(git -C "$HOME/drogon-source/trantor" rev-parse HEAD)" = 63a4e5e164e219dc3bf30cdbfa1462ae5602fa97
cmake -S "$HOME/drogon-source" -B "$HOME/drogon-build" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$HOME/drogon" \
  -DBUILD_TESTING=OFF -DBUILD_EXAMPLES=OFF -DBUILD_CTL=OFF -DBUILD_ORM=ON \
  -DUSE_POSTGRESQL=ON -DUSE_MYSQL=OFF -DUSE_SQLITE3=OFF -DUSE_REDIS=OFF
cmake --build "$HOME/drogon-build" --parallel 2
cmake --install "$HOME/drogon-build"
cd /path/to/examples/applications/device-heartbeats
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$HOME/drogon"
cmake --build build --parallel 2
clang-format --dry-run --Werror src/*.cpp src/*.hpp test/validation.cpp
ctest --test-dir build --output-on-failure
python3 test/preflight.py "$PWD/build/device_heartbeats"
```

The preflight mode exposes only `/health` without a database. Normal startup requires and verifies the configured runtime connection before opening the listener. CTest runs one executable containing three validation groups; the separate preflight exercises the compiled listener and waits for successful SIGTERM exit. CI repeats these local checks without Cloud credentials.

## Create your dedicated Cloud fixture

Use an authenticated [clickhousectl](https://github.com/ClickHouse/clickhousectl) CLI. Creation starts billing; delete your fixture after testing. Check the current supported region/shape for your organization. This modest no-HA shape was supported by the tested service:

```sh
umask 077
export ORG_ID=your-clickhouse-organization-id
clickhousectl cloud postgres create --org-id "$ORG_ID" \
  --name device-heartbeats-demo --provider aws --region us-east-1 \
  --size c6gd.large --pg-version 18 --ha-type none --json > /private/path/create.json
export PG_ID=your-created-service-id
clickhousectl cloud postgres get "$PG_ID" --org-id "$ORG_ID"
# Repeat get until state is running, then fetch the official PEM:
clickhousectl cloud postgres certs get "$PG_ID" --org-id "$ORG_ID" \
  --output /private/path/ca.pem
```

Keep the returned ID, hostname, username and one-time password privately. `--output` writes PEM even when CLI stdout is automatically JSON. Refresh the official bundle after certificate rotation. The app passes libpq `sslmode=verify-full`, the explicit hostname and `sslrootcert`; the full official bundle worked unchanged. Never replace verification with `require`.

## Bootstrap, migrate and seed

Copy `.env.example` to `/private/path/setup.env`, mode 600, outside the checkout. Fill in Cloud connection fields, `ADMIN_USER`/`ADMIN_PASSWORD` from creation, a separate `MIGRATION_PASSWORD`, `PGPASSWORD` for `heartbeats_app`, and two distinct project tokens. Paths must be absolute. Shell-safe quote private values when necessary. Export fields to child processes:

```sh
set -a; source /private/path/setup.env; set +a
export PGSSLMODE=verify-full
APP_PASSWORD=$PGPASSWORD
export PGUSER=$ADMIN_USER PGPASSWORD=$ADMIN_PASSWORD
psql -X -v MIGRATION_PASSWORD="$MIGRATION_PASSWORD" -v APP_PASSWORD="$APP_PASSWORD" \
  -f sql/bootstrap.sql
export PGUSER=heartbeats_migration PGPASSWORD=$MIGRATION_PASSWORD
psql -X -f sql/migrate.sql
psql -X -f sql/grants.sql
psql -X -f sql/seed.sql
```

Bootstrap creates the roles/schema and revokes PUBLIC database CREATE/TEMP and public-schema CREATE on this dedicated fixture. The schema owner needs no database CREATE. Versioned SQL uses an advisory transaction lock; migration and seed are repeatable. Seed adds north/south projects and meter-a/b/c without resetting stored readings. The server never runs migrations or runtime DDL.

The runtime gets SELECT on devices/samples, INSERT on samples, identity-sequence USAGE and UPDATE only on latest_sequence/sample_count. It cannot read migration history. Both project scopes share this role; project authorization lives in the API.

## Run and try

```sh
export PGUSER=heartbeats_app PGPASSWORD=$APP_PASSWORD
unset ADMIN_USER ADMIN_PASSWORD MIGRATION_PASSWORD
./build/device_heartbeats
```

The listener binds `127.0.0.1:4000`; PORT can change the local port. `/health` reports process readiness after startup, without continuously probing the database. SIGTERM stops the server and closes the pool. Create a private mode-600 runtime.env containing only PGHOST, PGPORT, PGDATABASE, PGUSER=heartbeats_app, its PGPASSWORD, PGSSLROOTCERT, NORTH_TOKEN, SOUTH_TOKEN and optional PORT. In a second shell:

```sh
set -a; source /private/path/runtime.env; set +a
curl -sS http://127.0.0.1:4000/devices -H "Authorization: Bearer $NORTH_TOKEN"
curl -sS http://127.0.0.1:4000/devices/meter-a/samples \
  -H "Authorization: Bearer $NORTH_TOKEN" -H 'Content-Type: application/json' \
  --data '{"sample_id":"aaaaaaaa-1234-4567-890a-123456789abc","sequence":"9007199254740993","reading":12,"observed_at":"2026-10-02T12:13:14Z"}'
curl -sS 'http://127.0.0.1:4000/devices/meter-a/samples?limit=25' \
  -H "Authorization: Bearer $NORTH_TOKEN"
```

New samples return 201; the same canonical payload returns 200/`replay=true` with identical retained fields. Changed payload, stale sequence or full history return 409. Unknown project-scoped device writes return 404; history reads return an empty page. Invalid credentials return 401. JSON media type is compared exactly, case-insensitively, before optional `;` parameters; duplicate keys, comments and trailing commas reject.

| Route | Bounds |
| --- | --- |
| GET `/devices?limit=25&after=meter-a` | ASCII device key ascending, scoped to token |
| POST `/devices/{device}/samples` | Required sample_id, sequence, reading; optional observed_at; no other fields |
| GET `/devices/{device}/samples?limit=25&before=123` | Numeric identity descending; before/IDs are decimal strings |

Lists default to 25, cap at 100 and return last-row `next_after`/`next_before`; finish on an empty page. Numeric ordering qualifies `heartbeats.samples.id`, avoiding the `id::text` output alias. Identity order is allocation order, not commit chronology; gaps are normal. Pages are live reads, not a snapshot.

Sequence is a decimal string 1–9223372036854775807, at most 19 digits, with no leading zero. Reading is an exact JSON integer from -1,000,000 through 1,000,000; booleans/floating-point JSON values reject. UUIDs normalize to lowercase. Observation time is null/omitted or whole-second UTC `YYYY-MM-DDTHH:MM:SSZ`, years 1970–2100 with a valid calendar date. Database `clock_timestamp()` records receipt when history is inserted after the parent lock; it is not device observation time or a commit timestamp.

Limits: 4 KiB body, 32 connections, two HTTP event-loop threads, ten-second connection idle timeout, 32 requests per keepalive connection, four pipelined requests, 12 admitted authenticated operations and eight admitted writes. The DB pool has four connections; Drogon's client acquisition/query timeout is five seconds, statement timeout four seconds, lock timeout two seconds and idle-in-transaction timeout six seconds. The connection string also sets `connect_timeout=5`, but libpq ignores that option during asynchronous `PQconnectPoll`; it is not an additional connection deadline here. These are individual controls, not a guaranteed total HTTP deadline. Runtime SQL is asynchronous; only startup connectivity is synchronous.

## Real Cloud acceptance

Use only a disposable dedicated fixture: tests add devices, triggers and owner-controlled history/counters. Stop the server. Restore setup credentials, reset, then rerun bootstrap/migration/grants/seed above (migration/seed can be repeated):

```sh
set -a; source /private/path/setup.env; set +a
export PGSSLMODE=verify-full
APP_PASSWORD=$PGPASSWORD
export PGUSER=$ADMIN_USER PGPASSWORD=$ADMIN_PASSWORD
psql -X -f sql/cleanup.sql
# Repeat bootstrap, migration twice, grants and seed twice as above.
export PGUSER=heartbeats_app PGPASSWORD=$APP_PASSWORD
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj /CN=UnrelatedAcceptanceCA \
  -keyout /private/path/wrong-ca.key -out /private/path/wrong-ca.pem
export WRONG_CA=/private/path/wrong-ca.pem
export HEARTBEATS_EXECUTABLE="$PWD/build/device_heartbeats"
export EVIDENCE_DIR=/private/path/acceptance
python3 test/cloud.py
```

The standard-library Python helper uses `psql` for independent controls. Its C++ child receives only runtime fields. Nine cases cover scoped validation/64-bit boundaries, actual two-session lock waits and UUID replay, competing sequences, ten post-history write failures followed by recovery, deferred COMMIT failure followed by same-ID 201/200, all 200 history rows in numeric pages, grants/constraints and the trusted-role bypass, actual wrong-CA/wrong-host certificate diagnostics with a positive DNS control, and old-process exit before durable restart/replay. Temporary fault triggers are owner-only and removed without widening runtime grants. Owner-accelerated full-history fixtures test the cap without implying device throughput.

## Cleanup

Stop the app. Optional schema destruction requires administrator credentials restored explicitly after the runtime steps unset them:

```sh
set -a; source /private/path/setup.env; set +a
export PGUSER=$ADMIN_USER PGPASSWORD=$ADMIN_PASSWORD PGSSLMODE=verify-full
psql -X -f sql/cleanup.sql
clickhousectl cloud postgres delete "$PG_ID" --org-id "$ORG_ID"
clickhousectl cloud postgres list --org-id "$ORG_ID"
```

Confirm your exact ID is absent. Cleanup leaves PUBLIC revocations in place and is fixture destruction, not a production downgrade. Retained history is bounded rather than evicted; longer-lived ingestion needs an explicit archival/replay policy.

Primary references: [Drogon 1.9.13 DbClient API](https://github.com/drogonframework/drogon/blob/v1.9.13/orm_lib/inc/drogon/orm/DbClient.h), [transaction implementation](https://github.com/drogonframework/drogon/blob/v1.9.13/orm_lib/src/TransactionImpl.cc), [libpq verified connection options](https://www.postgresql.org/docs/current/libpq-connect.html).
