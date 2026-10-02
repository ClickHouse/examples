# Task dependencies with Go, Gin and GORM

A bounded account-scoped task API on **ClickHouse Managed Postgres**. Create tasks inside a seeded project, add/remove prerequisites, and complete a task once its current prerequisites are done. The project lock makes one graph authoritative while competing changes are checked and committed.

Pinned stack: Go 1.27.1, Gin 1.12.0, GORM 1.31.2, GORM Postgres driver 1.6.3 and pgx 5.11.0. Native Linux ARM64 was tested; PostgreSQL 18 is the Cloud major. No browser interface, project creation, task deletion or reopening route is included. This is a loopback API with two synthetic accounts, not an identity provider.

## Transaction and graph rules

Every graph write begins a GORM transaction and locks the account-scoped project `FOR UPDATE`. It reads at most 100 tasks and 300 edges, validates the requested change, then updates the project revision and writes through **that same `tx` handle**. A task points toward its prerequisites; adding `A → B` cycles if B already reaches A. Opposing concurrent edges cannot both validate against an older graph.

Completion checks current prerequisites under the same lock as edge changes. A completed task cannot gain a new prerequisite. Existing edge additions return the original edge, removal is repeat-safe, and repeated completion returns the saved task without changing its timestamp/revision. Removing an existing prerequisite from a completed task is allowed; it does not reopen the task. Task creation generates a new UUID each time and is **not** repeat-safe after an ambiguous response: read the graph before deciding whether another task is needed.

The database enforces unique/no-self edges, composite foreign keys for both endpoints within the same project, and 100-task/300-edge insertion bounds. A project revision stays between 0 and 1,000,000,000; further changes conflict at the cap. Revisions are server output, not client optimistic-edit tokens. Snapshot reads hold a project `FOR SHARE` lock through their ordered task/edge queries, keeping the header and graph consistent with writers. Project lists use a UUID cursor, stable ascending order and a fixed 20-row limit. Graph reads use hard limits and reject unexpected oversized stored graphs.

No runtime `AutoMigrate`, `Save` insert fallback, or zero-value struct update is used. Explicit map/column updates check `Error` and `RowsAffected`; completion sets `done=true` and its timestamp with `RETURNING`.

## Build in native Linux

Use Go 1.27.1, Python 3.12+, `psql` and `clickhousectl` in a Linux filesystem. The `nomsgpack` build tag omits unused Gin MessagePack support; JSON is the only accepted write format.

```bash
go mod download
go mod verify
go test -tags nomsgpack ./...
go vet -tags nomsgpack ./...
mkdir -p bin
go build -tags nomsgpack -o bin/task-api ./cmd/server
```

`go.mod` and `go.sum` pin dependencies. Database-free units cover graph reachability, Unicode/UUID boundaries, strict JSON, credential configuration and foreign origins. Real Cloud controls skip unless explicitly enabled.

## Create a disposable Cloud fixture

Authenticate the CLI privately with your own API key. Choose your organization explicitly and confirm current region/size availability and pricing in the [Managed Postgres documentation](https://clickhouse.com/docs/products/managed-postgres/). This c6gd.large AWS fixture has no HA and incurs charges; do not use an existing production database for destructive failure controls.

```bash
export ORG_ID=your-organization-id
umask 077
mkdir -p .local/private
clickhousectl cloud postgres create \
  --name task-dependencies-demo --provider aws --region us-east-1 \
  --size c6gd.large --pg-version 18 --ha-type none \
  --org-id "$ORG_ID" --json > .local/private/create.json
export PG_ID=$(python3 -c 'import json; print(json.load(open(".local/private/create.json"))["id"])')
clickhousectl cloud postgres get "$PG_ID" --org-id "$ORG_ID" --json
# Repeat get until state is running before downloading its CA or connecting.
clickhousectl cloud postgres certs get "$PG_ID" --org-id "$ORG_ID" \
  --output .local/private/ca.pem
```

The creation receipt contains administrator credentials once; `get` does not recover the password. Keep four environment files outside Git, mode 600:

| File | Contents |
| --- | --- |
| `admin.env` | Common fields, administrator `PGUSER`/`PGPASSWORD`, generated `TASKS_OWNER_PASSWORD` and `TASKS_RUNTIME_PASSWORD` |
| `migration.env` | Common fields, `PGUSER=tasks_owner`, its password |
| `runtime.env` | Common fields, `PGUSER=tasks_runtime`, its password, distinct `TASKS_NORTH_TOKEN` and `TASKS_SOUTH_TOKEN` |
| `test.env` | `TEST_OWNER_USER=tasks_owner`, `TEST_OWNER_PASSWORD` only |

Common fields: `PGHOST`, `PGPORT=5432`, `PGDATABASE=postgres`, `PGSSLMODE=verify-full`, `PGSSLROOTCERT=/absolute/path/official-ca.pem`, `PGCONNECT_TIMEOUT=10`. Generate private passwords/tokens using `python3 -c 'import secrets; print(secrets.token_urlsafe(32))'`. Bearer tokens must differ and contain 32–256 bytes; they map to fixed synthetic north/south account UUIDs on the server. Never put credentials in URLs or committed source.

In a setup terminal:

```bash
set -a; source .local/private/admin.env; set +a
psql -X -f sql/bootstrap.sql
set -a; source .local/private/migration.env; set +a
bash scripts/migrate.sh up
psql -X -f sql/grants.sql
psql -X -f sql/seed.sql
```

Migration `up` is advisory-locked and checks the recorded SHA256. Repeating it verifies the checksum. Repeating seed inserts no duplicate projects/tasks/edges. `down` destroys this app’s data/objects while preserving the administrator-created schema and clears its migration version; follow with up/grants/seed only on a disposable fixture. Do not edit applied migrations.

## Run and use the API

Open a new terminal that has not sourced setup credentials. Export **only runtime credentials**:

```bash
set -a; source .local/private/runtime.env; set +a
./bin/task-api
```

The actual GORM driver receives a pgx/database/sql connection configured with the official CA and mandatory `verify-full`. Certificate and hostname checks stay enabled. The pool has four connections, 30-second idle and 15-minute connection lifetimes; connection timeout is five seconds, statements ten seconds and lock waits five seconds. HTTP time/header limits and an 8 KiB JSON write-body limit bound requests. Graceful shutdown joins before closing the pool.

From a private client terminal with the north token in `TOKEN`:

```bash
export TOKEN="$TASKS_NORTH_TOKEN"
curl -s http://127.0.0.1:8090/api/projects -H "Authorization: Bearer $TOKEN"
curl -s http://127.0.0.1:8090/api/projects/20000000-0000-4000-8000-000000000001 \
  -H "Authorization: Bearer $TOKEN"
curl -s http://127.0.0.1:8090/api/projects/20000000-0000-4000-8000-000000000001/tasks \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  --data-binary '{"title":"Check launch checklist"}'
```

Use returned task UUIDs in these routes; writes require `application/json` with exactly the documented object fields, no duplicates:

| Method/path below `/api/projects/:project` | Body/result |
| --- | --- |
| `GET` | Coherent project, ordered tasks and edges |
| `POST /tasks` | `{"title":"Review"}`; new task, HTTP 201 |
| `POST /tasks/:task/prerequisites` | `{"prerequisite_id":"UUID"}`; existing/new edge, HTTP 200 |
| `DELETE /tasks/:task/prerequisites/:prerequisite` | Repeat-safe HTTP 204 |
| `POST /tasks/:task/complete` | `{}`; completed/existing task, HTTP 200 |

Cycles, unresolved prerequisites, completed-task additions and caps return 409 with a public code. Cross-account or missing project/task UUIDs return 404; malformed paths/JSON return 400 and invalid titles 422. UUIDs are canonicalized. Titles reject Unicode controls and replacement characters, conservatively rejecting JSON lone surrogates decoded as U+FFFD; valid paired non-BMP text works. Database/internal errors return a generic 503 without raw SQL or credentials.

## Trust and omissions

All routes derive account identity from server-mapped bearer credentials; submitted IDs cannot choose an account. There are no ambient cookies or CORS permissions. Unsafe requests with a foreign `Origin` are rejected. Tokens have no expiry/revocation store: rotate the server’s token configuration and restart to revoke them. Production requires HTTPS, real credential issuance/rotation and appropriate perimeter limits; keep this demonstration on loopback.

The shared runtime role is trusted across both accounts. It can issue permitted direct SQL across accounts and bypass API cycle/prerequisite/monotonic-completion checks. There is no RLS, universal DAG constraint or database-enforced account authorization. Database endpoint/bound constraints still apply. The separate migration owner can change schema and data; runtime cannot assume that role, create schema objects/temp tables, change task titles/account ownership or delete tasks/projects.

## Actual Cloud acceptance and restart

Use only your disposable fixture. In a test terminal, export runtime plus test credentials, never into the running API:

```bash
python3 -m venv .venv
.venv/bin/pip install -r tests/requirements.txt
set -a; source .local/private/runtime.env; source .local/private/test.env; set +a
.venv/bin/python tests/acceptance.py
```

Nine HTTP cases exercise workflow/retries, direct/long cycles, observed opposing-edge contention, completion versus a new prerequisite, rollback after the revision UPDATE, account scope/composite keys, graph quotas, input/revision bounds and runtime privileges. Helpers create/delete their own owner-controlled fixtures and temporary failure trigger. They are not routes.

For actual GORM TLS and a paused SHARE reader versus an independent waiting HTTP writer, create the dedicated empty coherence fixture once using the test owner:

```bash
export PROBE_PROJECT_ID=20000000-0000-4000-8000-000000000099
PGUSER="$TEST_OWNER_USER" PGPASSWORD="$TEST_OWNER_PASSWORD" psql -X -c \
  "INSERT INTO task_dependencies.projects(id,account_id,name) VALUES ('$PROBE_PROJECT_ID','10000000-0000-4000-8000-000000000001','Coherence fixture')"
TASKS_CLOUD_TESTS=1 go test -tags nomsgpack ./internal/board -run TestCloud -count=1 -v
```

The TLS controls use the same GORM driver construction: an empty trust store and a substituted TLS server name must fail specifically for certificate/hostname verification. Application configuration uses the unchanged official CA/hostname. The coherence control observes a writer blocked by the exact reader backend, then compares old and subsequent complete snapshots. Repeating that test requires owner cleanup of its task and resetting the dedicated project revision.

After the tests, replace the exact app process and compare durable API state:

```bash
API_PID=your-api-pid EVIDENCE_DIR=/tmp/task-dependencies-evidence \
  .venv/bin/python tests/restart.py
```

This one-time helper creates its own persistence project, completes three tasks and two prerequisite edges, verifies executable/cwd, waits for the original process to exit, and starts a runtime-only replacement. It compares the exact project/revision, task completion timestamps and edges plus repeat completion. It records `persistence.json` and `replacement.pid`; stop the replacement during cleanup. Local CI needs no Cloud credentials.

## Cleanup

Stop the API process, then delete only the dedicated Cloud service you created and verify that exact ID is absent:

```bash
clickhousectl cloud postgres delete "$PG_ID" --org-id "$ORG_ID" --json
clickhousectl cloud postgres list --org-id "$ORG_ID" --json
```

Delete promptly after review to end fixture billing. If retaining Cloud while removing app objects, use an administrator terminal that explicitly restores receipt `PGUSER`/`PGPASSWORD` before dropping this example’s schema/roles. Do not clean up an unrelated or existing service.
