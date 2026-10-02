# Checklist runs with React, TanStack Query and PostgREST

A small TypeScript interface over a SQL-first API on **ClickHouse Managed Postgres (public beta)**. Choose a versioned template, start a labelled run and complete its steps with retained notes. Two synthetic operator roles see their own runs and nested records. No external task service or analytical database is required.

The UI uses React 19.3.0, TanStack Query 5.104.1 and Vite 8.3.2. TypeScript 7.0.2, Node 24.21.0 LTS, PostgREST 16.4 and helper dependencies are pinned. PostgreSQL 18 is the documented Cloud major. This is a loopback demo: Vite preview is not production hosting, and the offline fixture token issuer is not a login provider.

## What stays correct

`start_run` locks the current operator row, checks the retained request UUID and the 100-run lifetime quota, then copies all template steps and saves its initial response in one transaction. Matching canonical payloads replay that original response even after completion. Changed payloads conflict. Labels and notes trim surrounding spaces; template UUIDs and run IDs use PostgreSQL's native canonical types. Sequence values can have gaps after rollback.

`complete_step` locks the scoped parent run. It checks a retained completion before closed state, so a matching replay remains valid after the run completes. Otherwise it rejects a completed run, a missing step or a step already completed under another key. Counter update, immutable completion insertion and retained result share the native PostgREST request transaction. Both write RPCs are `VOLATILE` and use POST; GET is read-only and cannot perform their writes.

The browser marks completion only after confirmation. A failed or ambiguous action keeps the exact UUID and captured payload until retry succeeds or the operator explicitly clears it. Retry is safe within that action; clearing, disconnecting or refreshing does not undo an already committed write. Keep a request UUID outside the tab if recovery must survive refresh.

Run IDs and cursors are decimal **strings**, including JSONB retained results and nested records. The `list_runs` RPC compares and orders the underlying qualified bigint column, returning at most 20 rows; the UI requests 10. This is live keyset pagination in creation order, not a frozen snapshot. Templates contain at most 10 steps, and each operator retains at most 100 runs including completed ones. There is no delete/archive route.

## Install on Linux

Use a native Linux directory and Node 24.21.0 LTS, Python 3.12+, `psql`, and the ClickHouse CLI. All language dependencies and tests belong in that Linux environment. From this application directory:

```bash
python3 scripts/install_postgrest.py
.local/bin/postgrest --version
npm ci
npm run build
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

The installer supports ARM64 and x86-64, downloads the exact [official PostgREST 16.4 release](https://github.com/PostgREST/postgrest/releases/tag/v16.4) and checks its published SHA256 before writing `.local/bin/postgrest`. The npm lockfile fixes the UI and patched Playwright 1.63.0 helper. No browser dependency is needed to serve the app.

## Create a dedicated Cloud fixture

Authenticate `clickhousectl` using your own Cloud API key outside source files. Choose the organization explicitly. The following no-HA AWS fixture is billable; confirm current size/region availability and pricing in the [Managed Postgres documentation](https://clickhouse.com/docs/products/managed-postgres/). Do not reuse a production service for the destructive acceptance controls.

```bash
export ORG_ID=your-organization-id
umask 077
mkdir -p .local/private
clickhousectl cloud postgres create \
  --name checklist-runs-demo --provider aws --region us-east-1 \
  --size c6gd.large --pg-version 18 --ha-type none \
  --org-id "$ORG_ID" --json > .local/private/create.json
export PG_ID=$(python3 -c 'import json; print(json.load(open(".local/private/create.json"))["id"])')
clickhousectl cloud postgres get "$PG_ID" --org-id "$ORG_ID" --json
# Repeat get until state is running before connecting or retrieving its CA.
clickhousectl cloud postgres certs get "$PG_ID" --org-id "$ORG_ID" \
  --output .local/private/ca.pem
```

The create receipt supplies the administrator hostname, username and password once. Keep it private. Create four mode-600 environment files, using absolute certificate paths:

| File | Contents |
| --- | --- |
| `admin.env` | Common connection fields plus receipt `PGUSER`/`PGPASSWORD`, generated `CHECKLIST_OWNER_PASSWORD` and `CHECKLIST_AUTH_PASSWORD` |
| `migration.env` | Common fields plus `PGUSER=checklist_owner` and its password |
| `runtime.env` | Common fields plus `PGUSER=checklist_authenticator`, its password and `PGRST_JWT_SECRET` |
| `test.env` | `TEST_OWNER_USER=checklist_owner`, `TEST_OWNER_PASSWORD` only |

Common fields are `PGHOST`, `PGPORT=5432`, `PGDATABASE=postgres`, `PGSSLMODE=verify-full`, `PGSSLROOTCERT=/absolute/path/ca.pem`, and `PGCONNECT_TIMEOUT=10`. Generate distinct database passwords locally with `python3 -c 'import secrets; print(secrets.token_urlsafe(30))'`, and the JWT secret with `python3 -c 'import secrets; print(secrets.token_hex(64))'`. Do not put these values in `VITE_*` variables, client code, URLs or Git.

### Bootstrap and migrate

Use a setup terminal. `set -a` exports the private file values to child processes:

```bash
set -a; source .local/private/admin.env; set +a
psql -X -f sql/bootstrap.sql
set -a; source .local/private/migration.env; set +a
bash scripts/migrate.sh up
psql -X -f sql/grants.sql
psql -X -f sql/seed.sql
```

The migration takes an advisory lock and records its checksum. Repeating `up` checks the checksum and does not recreate objects; repeating the seed does not add duplicates. `down` removes this example's objects and data while preserving its administrator-created schemas; apply `up`, grants and seed afterward only on a disposable fixture. Migration/grants send `NOTIFY pgrst, 'reload schema'`; a running PostgREST reloads its schema cache. Send the same notification after later API schema changes. Do not edit an applied migration in place.

### Start the two local processes

Open a new terminal that has not sourced setup credentials. Export **only** `runtime.env`, then start PostgREST:

```bash
set -a; source .local/private/runtime.env; set +a
.local/bin/postgrest postgrest.conf
```

PostgREST uses libpq environment variables, the official CA and `sslmode=verify-full` for certificate and hostname verification. It exposes only `checklist_api`. Its finite pool has four connections, a five-second acquisition timeout and 900-second maximum lifetime; role settings impose 10-second statements and five-second lock waits. Automatic database recovery is disabled so connection failure exits visibly.

In a separate terminal with **no database or signing credentials**:

```bash
npm run dev
# Or demonstrate the built assets locally:
npm run build
npm run preview
```

Open `http://127.0.0.1:5173`. Both Vite modes proxy same-origin `/api` requests to loopback PostgREST on port 3000. Allowed hosts and API CORS origins are restricted to the local UI; there is no wildcard workaround.

In the private runtime terminal, issue a fixture token and paste it into the UI password field:

```bash
python3 scripts/tokens.py checklist_north --seconds 900
# The second synthetic scope:
python3 scripts/tokens.py checklist_south --seconds 900
```

The JWT remains in tab memory. Each connection owns a fresh QueryClient; disconnect cancels queries and clears its cache. A delayed old response cannot populate a new connection. Mutations already sent may still commit under the old role. Tokens expire without a revocation table: native PostgREST allows 30 seconds of clock skew. The pre-request check additionally requires an explicit audience, issued-at and expiry, and at most 900 seconds between them. It does not claim a logout/revocation provider.

## Direct API examples

Store a freshly issued token in the local shell variable `TOKEN`, without placing it in a URL:

```bash
export TOKEN=$(python3 scripts/tokens.py checklist_north)
curl -s http://127.0.0.1:3000/templates -H "Authorization: Bearer $TOKEN"
curl -s http://127.0.0.1:3000/rpc/start_run \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  --data-binary @examples/start.json
curl -s 'http://127.0.0.1:3000/rpc/list_runs?p_after=0&p_limit=10' \
  -H "Authorization: Bearer $TOKEN"
```

Copy the returned string run ID into `examples/complete.json`, then POST it to `/rpc/complete_step`. Retain each request UUID when retrying. Read a detail using `/runs?id=eq.ID&select=*,run_steps(*),completions(*)`; computed relationships preserve the caller's RLS policies. Cross-scope reads return empty rows, and cross-scope completion returns 404. Payload/key conflicts and closed changes return 409; bounded scalar validation returns 422. Malformed JSON, UUIDs or bigint casts can return native 400. These are native REST statuses, not an application wrapper.

## Authorization and limits

The authenticator is `LOGIN NOINHERIT` with membership only in `checklist_north` and `checklist_south`, both `NOLOGIN`. It has no schema-owner membership. PostgREST validates the JWT and applies `SET LOCAL ROLE`; RLS uses that database role, never a submitted scope. `security_invoker` views and RPCs retain the caller's policies. Exposed views grant SELECT only, so HTTP clients cannot patch notes or directly alter counters/templates. Completion rows have no API-role UPDATE/DELETE grant. Template versions are inserted by the trusted migration owner; the API cannot modify them.

Invoker RPCs need narrow underlying INSERT/UPDATE grants. A stolen authenticator credential can impersonate either granted scope and issue direct SQL outside RPC workflow checks. RLS still separates the chosen role, but it is not protection against this shared credential. Owner/admin credentials remain trusted and can bypass RLS. No SECURITY DEFINER helper is used.

`db-max-rows=20` limits each fetched relation, not HTTP body size, embed computational cost or a JSON scalar response's internal array. RPC scalar bounds, the 100-run quota, 10-step snapshots and finite statement/lock timeouts are additional controls. This local example does not implement a general query-cost firewall or public HTTP size/rate limiter. Put production hosting, HTTPS, request limits and a real identity provider in front of it before public use.

## Meaningful verification

Tests require this disposable Cloud fixture with PostgREST running. In a test-only terminal, export runtime plus test credentials, never into the PostgREST child:

```bash
python3 -m venv .venv
.venv/bin/pip install -r tests/requirements.txt
set -a; source .local/private/runtime.env; source .local/private/test.env; set +a
.venv/bin/python tests/acceptance.py
POSTGREST_BIN=.local/bin/postgrest python3 tests/tls.py
npx playwright install --with-deps chromium
EVIDENCE_DIR=/tmp/checklist-evidence npm run test:browser
```

The HTTP suite observes independent transactions blocked on actual rows, matching concurrent starts/completions, full rollback after the counter update and child failure, retained closed-state replays, nested RLS, failed JWTs, runtime privilege boundaries, read-only GET writes, quotas and exact IDs beyond JavaScript's safe-integer range. Owner-controlled failure triggers and sequence/fixtures are test scaffolding, not application routes. Browser evidence verifies committed step states, ambiguous retry, identity switching, delayed old responses, expiry and desktop/mobile layout. Keep raw failures separately when correcting a helper. Local CI needs no Cloud credentials.

To reproduce persistence, first run the browser helper above with a fixed `EVIDENCE_DIR`; it records `browser-snapshot.json`. Keep the UI process running. In the same test terminal, supply the PID of this app’s running PostgREST process and its installed binary:

```bash
POSTGREST_PID=your-postgrest-pid POSTGREST_BIN=.local/bin/postgrest \
  EVIDENCE_DIR=/tmp/checklist-evidence .venv/bin/python tests/restart.py
EVIDENCE_DIR=/tmp/checklist-evidence node tests/restart_browser.mjs
```

The helper verifies the PID’s executable and working directory, waits for its exit, and starts a replacement with only runtime credentials. It compares the exact saved run, all step/completion data and retained start/completion replies, then the browser uses a fresh token to read the completed run. The replacement PID is saved in `EVIDENCE_DIR/replacement.pid`; stop that process during cleanup.

## Cleanup

Stop the two local processes. Delete only the dedicated fixture you created and check that its exact ID is absent:

```bash
clickhousectl cloud postgres delete "$PG_ID" --org-id "$ORG_ID" --json
clickhousectl cloud postgres list --org-id "$ORG_ID" --json
```

Deletion removes the database and its data; stop fixture billing promptly after review. If retaining the service while removing only the app, use a separate administrator terminal that explicitly restores receipt `PGUSER`/`PGPASSWORD` before dropping these schemas and roles. Never run cleanup against another application or an existing service.
