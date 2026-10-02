# Playlist API with gqlgen and Ent

A compact GraphQL API composes playlists over synthetic track metadata in ClickHouse Managed Postgres. There is no audio, upload, streaming, commercial catalogue or music-service integration. Two environment bearer tokens identify fixed server-side accounts. Create a named playlist, read its ordered metadata and reorder its existing tracks with the revision you observed.

## Verified native stack

Use native Linux with Go 1.27.1, Python 3/venv for checks, curl, and `psql`. This example was generated and compiled on Ubuntu 24.04 ARM64 **before** database allocation. Exact released pins: Go 1.27.1, gqlgen 0.17.95, Ent 0.14.6, ent/contrib 0.7.0 and pgx 5.11.0. `go.mod` and `go.sum` commit the dependency graph; generated Ent and gqlgen code is checked in. Some transitive generator modules use fixed upstream pseudo-versions; no floating `latest` appears in generation commands. See [official Go downloads](https://go.dev/dl/) for the correct native architecture archive and checksum.

```bash
go mod download
go generate ./...
go test ./...
python3 scripts/check-generation.py
go build -o .local/playlist-api ./cmd/server
```

Regeneration is deterministic and checks Go/module source bytes before and after. Runtime never calls Ent `Schema.Create`. Owner-applied SQL is authoritative: the Ent position index expresses uniqueness, while the explicit SQL migration makes that uniqueness **DEFERRABLE INITIALLY DEFERRED**. Replacing this setup with automatic Ent migration would lose that ordering contract. Keep the Ent schemas and versioned SQL together.

## Create a dedicated Cloud fixture

Install/configure [clickhousectl](https://github.com/ClickHouse/clickhousectl) with your Cloud API credentials. Confirm current [supported regions/sizes](https://clickhouse.com/docs/products/managed-postgres/) and [pricing](https://clickhouse.com/pricing). The tested service used AWS us-east-1, c6gd.large, PostgreSQL 18 and no HA. Compute/storage are billable; stopping the API does not remove the database.

```bash
mkdir -p "$HOME/playlist-private"
chmod 700 "$HOME/playlist-private"
clickhousectl cloud postgres create --name playlist-api-demo \
  --provider aws --region us-east-1 --size c6gd.large --pg-version 18 \
  --ha-type none --tag purpose=playlist-api --org-id YOUR_ORG_ID \
  --json > "$HOME/playlist-private/create.json"
chmod 600 "$HOME/playlist-private/create.json"
clickhousectl cloud postgres get YOUR_SERVICE_ID --org-id YOUR_ORG_ID --json
```

Read the ID from the private one-time receipt. Repeat `get` until running with a hostname, then retrieve the official CA:

```bash
clickhousectl cloud postgres certs get YOUR_SERVICE_ID --org-id YOUR_ORG_ID \
  --output "$HOME/playlist-private/ca.pem"
chmod 600 "$HOME/playlist-private/ca.pem"
```

Create four private shell env files (mode 600), with receipt hostname, port, database and absolute `PGSSLROOTCERT` path, plus `PGSSLMODE=verify-full` for setup:

* `admin.env`: receipt PGUSER/PGPASSWORD, plus new random PG_MIGRATION_PASSWORD and PG_APP_PASSWORD.
* `migration.env`: PGUSER=playlist_owner and its password.
* `runtime.env`: PGUSER=playlist_app and its password, ACCOUNT_A_TOKEN and ACCOUNT_B_TOKEN.
* `test.env`: TEST_OWNER_USER=playlist_owner and TEST_OWNER_PASSWORD, used only for opt-in live checks.

Generate passwords/tokens privately with `python3 -c 'import secrets; print(secrets.token_urlsafe(32))'`. Tokens must be distinct URL-safe strings of 32–128 characters. They map to the two seeded account UUIDs; clients cannot supply an owner. They are long-lived bearer credentials loaded at startup, without expiry, per-user identity or stored revocation. Use explicit Authorization headers, never query-string tokens. This tutorial binds loopback; a real deployment requires HTTPS and appropriate token distribution. There are no browser cookies, CORS allowances, subscriptions, multipart uploads or global node/CRUD endpoints.

## Owner setup and runtime

Never run the bootstrap on a shared database: it changes PUBLIC database/schema creation privileges. In separate exported subshells:

```bash
(set -a; source "$HOME/playlist-private/admin.env"; set +a
 psql -X -v ON_ERROR_STOP=1 -f scripts/bootstrap.sql)
(set -a; source "$HOME/playlist-private/migration.env"; set +a
 scripts/migrate.sh up
 psql -X -v ON_ERROR_STOP=1 -f scripts/grants.sql
 psql -X -v ON_ERROR_STOP=1 -f scripts/seed.sql)
```

`up` takes an advisory lock, verifies the stored checksum on repeat and refuses changed applied SQL. `down` destroys this app's tables/data; use only on your dedicated fixture. A fresh down/up cycle requires reapplying grants and seed. Seeding the two accounts and 60 synthetic tracks is repeat-safe. Runtime has SELECT, necessary playlist/item INSERT, playlist revision UPDATE and item position UPDATE. Tracks are SELECT-only; no app role DDL, DELETE or temporary tables.

The shared database role is **trusted** across accounts. It can query either account directly and can insert/update item positions outside API revision checks. The parent complete-items trigger checks on playlist insertion/update, not every direct item edit. There is no RLS or universal immutable-membership guarantee against arbitrary direct SQL. The API exposes no membership editing after creation and scopes every parent read/write by authenticated owner.

Open a new terminal that has not sourced setup credentials, then export only runtime env:

```bash
set -a; source "$HOME/playlist-private/runtime.env"; set +a
.local/playlist-api
```

The pool has at most four connections. pgx's database/sql adapter uses the downloaded CA and full hostname verification, with no insecure or plaintext fallback. Connect/ping, SQL statement and lock deadlines are 10/10/8 seconds. HTTP headers/read/write have 5/10/30-second bounds; each response has 25 seconds, followed by up to 30 seconds for joined graceful shutdown before the Ent client closes. Requests are at most 16 KiB. SQL parameters, tokens and payloads are never logged by diagnostics.

## Reproducible GraphQL workflow

```bash
curl --fail-with-body http://127.0.0.1:8080/query \
  -H "Authorization: Bearer $ACCOUNT_A_TOKEN" -H 'Content-Type: application/json' \
  --data-binary @examples/create.json
curl --fail-with-body http://127.0.0.1:8080/query \
  -H "Authorization: Bearer $ACCOUNT_A_TOKEN" -H 'Content-Type: application/json' \
  --data-binary @examples/list.json
```

Put the returned playlist UUID and observed revision into examples/reorder.json, then submit it the same way. Positions are 1-based, each playlist has 1–50 distinct existing tracks, names have 1–80 characters, and each account has at most 100 playlists. Names reject controls and U+FFFD: Go JSON decoding replaces escaped lone surrogates with that rune, so rejecting it conservatively also rejects an intentionally supplied replacement character. Valid paired non-BMP Unicode remains supported. Create commits the parent and complete ordered membership together. Reorder takes an owner-scoped parent FOR UPDATE lock, compares the supplied revision, requires an exact membership permutation, rewrites positions and advances revision once. The deferrable position constraint permits swaps without an intermediate uniqueness failure. A stale revision returns a GraphQL STALE error; invalid membership returns INVALID. Creation is not request-idempotent: retrying a successful create can add another playlist.

The pinned `entgql.Transactioner` opens a mutation transaction around response execution, serializes resolver middleware and commits after selections finish. Every resolver obtains `ent.FromContext`; there is no global-client fallback. Only **one expanded top-level mutation field occurrence** is allowed per operation, conservatively counting aliases, inline/named fragments and skipped branches. Multiple fields are rejected before opening a transaction, rather than promising batch atomicity. A deferred commit failure returns errors with no success data and rolls back all writes. Ordinary resolver domain failures use HTTP 200 with GraphQL errors; inspect the JSON body, not only curl's HTTP success.

Queries use one read-only repeatable-read transaction for a coherent revision and order across eager SELECTs. Ent loads items ordered by position and their tracks together; DTO response fields never fall back to per-item database queries. Page limits are 1–10, ordered by UUID ascending with a validated opaque account-bound cursor. This is a live keyset listing, not a frozen snapshot; inserts below a previous cursor can be missed when continuing. Track metadata queries have a 50-row limit. A page plus its sentinel reads at most 11 playlists and 550 items.

Operation policy permits depth at most 5, at most 100 expanded selections and at most 5 top-level query fields. Introspection is disabled. Custom saturated complexity multiplies validated playlist limits and the 50-item bound; excessive aliases/fan-out are rejected before expensive SQL. The total cost limit is 6000. Bad limits are rejected before querying. The schema has no recursive backreferences.

## Real validation

Basic CI runs generation/format/build and six database-free policy/boundary tests. Cloud checks are separate and never silently skipped. They require a running runtime server and exported runtime/test env. Enable `QUERY_COUNT_EVIDENCE=1` only for private diagnostic evidence and redirect server output to a portable log:

```bash
export SERVER_LOG=/tmp/playlist-api-server.log
QUERY_COUNT_EVIDENCE=1 .local/playlist-api > "$SERVER_LOG" 2>&1
```

Run helpers in a separate shell:

```bash
python3 -m venv .venv
.venv/bin/pip install -r tests/requirements.txt
.venv/bin/pip check
(set -a; source "$HOME/playlist-private/runtime.env"; source "$HOME/playlist-private/test.env"; set +a
 export SERVER_LOG=/tmp/playlist-api-server.log
 .venv/bin/python tests/acceptance.py
 .venv/bin/python tests/unicode_regression.py)
(set -a; source "$HOME/playlist-private/runtime.env"; set +a
 go test -tags cloud -v -count=1 ./internal/app)
```

Live fixtures prove independent real lock contention, child-write and deferred commit rollback, account/nested scope, exact permutation/position constraints, bounded queries and trusted-role limits. The Cloud-tagged tests exercise actual pgx certificate/hostname failures and pause the first eager header SELECT while another HTTP reorder commits. Read-only repeatable-read keeps the old complete snapshot, and a fresh query sees the new order. Diagnostic counts measure Ent-issued statements, excluding BEGIN/COMMIT and trigger-internal SQL; they are not throughput benchmarks.

## Cleanup

Stop the Go process and wait for its exit. Delete only your exact service ID, with explicit organization:

```bash
clickhousectl cloud postgres delete YOUR_SERVICE_ID --org-id YOUR_ORG_ID --json
clickhousectl cloud postgres list --org-id YOUR_ORG_ID --json
```

Deletion is asynchronous; verify that exact ID becomes absent. If retaining the database, restore administrator receipt PGUSER/PGPASSWORD before any schema/role removal, rather than reusing runtime credentials. Stop/preserve the VM after saving source and private evidence; do not delete it.
