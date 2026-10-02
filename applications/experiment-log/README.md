# Experiment log

A small Scala API records supplied experiment results in ClickHouse Managed Postgres. Two seeded projects have separate bearer tokens. Each immutable run contains a title, a bounded flat JSONB configuration and 1–10 exact decimal measurements. These are synthetic examples, not model training or scientific validation.

## Requirements and verified versions

Use a native Linux environment with OpenJDK 21, curl, PostgreSQL `psql`, and a dedicated Cloud Postgres service. The checked set is Scala 3.9.0, sbt 1.13.0, http4s/Ember 0.23.38, Cats Effect 3.7.1, doobie **1.0.0-RC13** (a maintained published release candidate, not stable 1.0), Circe 0.14.16, HikariCP 7.1.0 and pgJDBC 42.7.13. Exact direct versions and the selected transitive dependency record are committed. The wrapper verifies its pinned sbt launcher SHA-256; `verifyDependencyLock` rejects resolver drift. No snapshots are used.

The native CPU build was checked before allocating the database. Testing used Ubuntu 24.04 ARM64, OpenJDK 21.0.12.1 and PostgreSQL 18.6 on 2 October 2026. See [Cloud Postgres documentation](https://clickhouse.com/docs/products/managed-postgres/) for provisioning and the service CA.

## Dedicated database setup

Run from this application directory. Keep receipt credentials and the downloaded Cloud CA outside the clone, restrict private files to mode 600, and do not commit them. Never use this bootstrap on a shared database: it changes PUBLIC database/schema creation privileges.

Install/configure [clickhousectl](https://github.com/ClickHouse/clickhousectl) with your own Cloud API credentials. Verify current supported size/region and [pricing](https://clickhouse.com/pricing) before creation. This dedicated fixture used AWS us-east-1, `c6gd.large`, PostgreSQL 18 and no HA; it incurs compute/storage charges. Stopping the API does not remove the database.

```bash
mkdir -p $HOME/experiment-private
chmod 700 $HOME/experiment-private
clickhousectl cloud postgres create --org-id YOUR_ORG_ID \
  --name experiment-log --region us-east-1 --provider aws \
  --size c6gd.large --pg-version 18 --ha-type none \
  --tag purpose=experiment-log --json > $HOME/experiment-private/create.json
chmod 600 $HOME/experiment-private/create.json
clickhousectl cloud postgres get YOUR_SERVICE_ID --org-id YOUR_ORG_ID --json
```

Take `YOUR_SERVICE_ID` from the private receipt. Wait until `get` reports running, with its hostname populated, before retrieving the CA:

```bash
clickhousectl cloud postgres certs get YOUR_SERVICE_ID \
  --org-id YOUR_ORG_ID --output $HOME/experiment-private/ca.pem
chmod 600 $HOME/experiment-private/ca.pem
```

Create four private shell environment files. Each includes the receipt hostname, port, database, `PGSSLROOTCERT` (absolute CA path), and `PGSSLMODE=verify-full`:

* `admin.env`: receipt `PGUSER`/`PGPASSWORD`, plus `PG_MIGRATION_PASSWORD` and `PG_APP_PASSWORD` for two newly generated role passwords.
* `migration.env`: `PGUSER=experiment_owner` and its password.
* `runtime.env`: `PGUSER=experiment_app` and its password, plus distinct `PROJECT_A_TOKEN` and `PROJECT_B_TOKEN`.
* `test.env`: `TEST_OWNER_USER=experiment_owner` and `TEST_OWNER_PASSWORD` for opt-in acceptance only.

Generate each token with `python3 -c 'import secrets; print(secrets.token_urlsafe(32))'`. Do not put tokens in URLs or screenshots. The API uses explicit Authorization headers; there are no cookies, browser sign-in, CORS allowances or UI. Bind locally for this tutorial; use HTTPS and proper token distribution for a real deployment. Tokens identify fixed seeded project UUIDs and are loaded at process startup. They are long-lived bearer credentials; this example does not implement per-user identity, expiry, audit trails or token revocation storage.

In separate subshells, use the correct role for each step:

```bash
(set -a; source $HOME/experiment-private/admin.env; set +a
 psql -X -v ON_ERROR_STOP=1 -f scripts/bootstrap.sql)
(set -a; source $HOME/experiment-private/migration.env; set +a
 scripts/migrate.sh up
 psql -X -v ON_ERROR_STOP=1 -f scripts/grants.sql
 psql -X -v ON_ERROR_STOP=1 -f scripts/seed.sql)
```

The bootstrap creates `experiment_owner`, `experiment_app` and the schema. Runtime can SELECT and INSERT only the required columns; it cannot update/delete runs or children, set timestamps/transaction IDs, or create tables. The shared runtime database role is trusted across both projects; project isolation is enforced by the API's server-derived identity, not PostgreSQL row-level security.

`migrate.sh up` takes an advisory transaction lock and verifies the recorded file checksum on repeat. Seed is repeat-safe. `migrate.sh down` removes app data and tables; use it only on this dedicated fixture. To check a fresh migration cycle before recording data, run down/up as owner, then reapply grants and seed. Keep administrator credentials out of the runtime environment.

## Build and run

```bash
scripts/sbtw clean scalafmtCheckAll compile test verifyDependencyLock writeRuntimeClasspath
```

Start from a fresh shell containing **only** `runtime.env` and normal process variables. Do not source administrator, migration or test files in that shell:

```bash
set -a; source $HOME/experiment-private/runtime.env; set +a
java -Xmx768m -XX:ActiveProcessorCount=2 \
  -cp "$(cat .local/runtime-classpath.txt)" experimentlog.Main
```

The server binds `127.0.0.1:8080` and checks that the two seeded project IDs match its configured token identities. pgJDBC requires the actual Cloud CA with `sslmode=verify-full`, including hostname verification. Hikari owns four connections, with bounded connect/validation waits. SQL statements are limited to 10 seconds, locks to 8, socket reads to 15. Headers have a 5-second deadline, request JSON is at most 16 KiB with a 5-second body deadline, and the response middleware has a 30-second deadline. SQL parameter logging is disabled.

## Record, replay and search

```bash
curl --fail-with-body http://127.0.0.1:8080/runs \
  -H "Authorization: Bearer $PROJECT_A_TOKEN" \
  -H 'Content-Type: application/json' --data-binary @sample-run.json
curl --fail-with-body http://127.0.0.1:8080/runs/search \
  -H "Authorization: Bearer $PROJECT_A_TOKEN" \
  -H 'Content-Type: application/json' \
  --data '{"config":{"optimizer":"adam"},"title":"comparison","limit":5}'
```

Registration returns 201; an identical retained request returns 200 and its original complete response. Reuse the sample UUID to observe replay, or generate a new UUID for another run. Reusing a UUID with changed semantic content returns 409. The UUID is retained for the lifetime of its project data, without expiry or deletion in this example. Whitespace around titles is trimmed; configuration object order, measurement array order and decimal trailing zeros do not change the semantic payload. Changing a configuration string's whitespace does change it.

Measurement names match `[a-z][a-z0-9_]{0,31}` and are unique. Values are **plain decimal strings**, absolute value at most 1,000,000 and at most six fractional digits. They pass through Scala `BigDecimal`, doobie and unconstrained PostgreSQL `numeric`; a CHECK rejects excess scale instead of silently rounding it. Responses return decimal strings. No `Double` participates in the storage path.

Configuration is an object of at most ten ASCII keys (`[A-Za-z][A-Za-z0-9_]{0,23}`), with bounded strings, booleans or exact JSON numbers of magnitude at most 1,000,000 and normalized scale at most six. Null, arrays, nested objects, controls, unpaired Unicode surrogates, duplicate object keys and oversized numeric/exponent lexemes are rejected. GET `/runs/:id` retrieves a project-scoped run; GET `/project` returns the authenticated project ID.

Search applies parameterized JSONB `@>` containment plus an optional literal title substring. `%`, `_` and backslash are escaped. Empty `{}` matches every configuration. Page size is 1–20 (default 10), ordered by `(created_at,id)` descending. Pass `nextCursor` as `cursor` to continue. This is a validated opaque keyset cursor over a **live** listing, not a frozen snapshot: later inserts can appear above an existing cursor. Populated pages use two prepared SELECT statements, loading all selected child rows together; immutable committed runs make the pair consistent. The GIN `jsonb_path_ops` index supports containment; a small fixture may correctly use a sequential scan. No speed claim is made.

The parent and complete measurement set are one `ConnectionIO` with one `transact` at the HTTP boundary. The unique `(project_id,request_id)` key arbitrates races; the losing `ON CONFLICT DO NOTHING` statement is followed by a fresh READ COMMITTED lookup. A deferred constraint checks complete children at commit, and a transaction-ID trigger prevents attaching later measurements to an already committed run. This database role is trusted to submit its own consistent initial payload; it is not a sandbox for arbitrary hostile SQL.

## Verification

CI runs only formatting, compile, six boundary/semantic unit tests and dependency-record verification, without database credentials. Opt-in live checks need the running API, runtime env and test env:

```bash
python3 -m venv .venv
.venv/bin/pip install -r tests/requirements.txt
.venv/bin/pip check
(set -a; source $HOME/experiment-private/runtime.env; source $HOME/experiment-private/test.env; set +a
 .venv/bin/python tests/acceptance.py)
scripts/sbtw Test/compile writeTestClasspath
(set -a; source $HOME/experiment-private/runtime.env; set +a
 java -Xmx512m -cp "$(cat .local/test-classpath.txt)" experimentlog.LiveProbe)
```

Acceptance uses independent HTTP clients with observed database lock contention, a controlled owner-installed after-child failure and runtime privilege checks. The test-only TLS hostname control passes the actual TLS session to pgJDBC's native verifier with a substituted incorrect name; the application retains its default verifier. LiveProbe also performs actual doobie SQL type analysis, observes two prepared statements for a populated search, and prints the actual GIN definition and unforced plan. Its test classes are absent from the production classpath. Live checks are never silently skipped by CI.

## Stop and remove the dedicated fixture

Stop the JVM first. Delete only the exact Cloud service ID you created, using the explicit organization:

```bash
clickhousectl cloud postgres delete YOUR_SERVICE_ID --org-id YOUR_ORG_ID --json
clickhousectl cloud postgres list --org-id YOUR_ORG_ID --json
```

Deletion is asynchronous; verify that exact ID becomes absent. If retaining the service, use the administrator receipt (not runtime credentials) to drop the dedicated schema/roles after stopping all connections. Never run cleanup against another service. The VM can be stopped and preserved; source and private evidence should be saved separately before shutdown.
