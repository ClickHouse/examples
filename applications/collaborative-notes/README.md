# Collaborative notes with Hocuspocus, Yjs and Postgres

A small trusted workspace for three shared plain-text notes. Two editors can type, delete, work offline and reconnect. CodeMirror binds directly to `Y.Text`; Hocuspocus synchronizes updates. ClickHouse Managed Postgres stores original binary CRDT snapshots in `BYTEA`.

Synchronization and persistence have separate UI messages. A synchronized editor is **not** a database receipt. A snapshot receipt is broadcast only after its captured update has been merged and committed. Later edits can still be pending. An abrupt server loss can lose uncommitted edits.

This is one loopback server process and one trusted workspace, without application accounts, remote cursor awareness or horizontal coordination. All token holders can edit all three notes. The token stays in browser memory, never URLs or browser storage. Rotate it by changing the private environment and restarting the server; there is no per-user revocation. Do not expose this local demo to a public network.

## Requirements and install

Tested on 2 October 2026 with Linux ARM64, Node 24.21.0 LTS, TypeScript 7.0.2, Hocuspocus server/provider 4.7.0, Yjs 13.6.33, React 19.3.0, Vite 8.3.2, node-postgres 8.23.1 and PostgreSQL 18.6. Exact packages and transitive dependencies are locked in `package-lock.json`. Browser helpers use Playwright 1.63.0.

```bash
cd applications/collaborative-notes
npm ci
npm run build
npm test
npm run format:check
```

The production client bundle includes CodeMirror and Yjs; Vite reports its normal 500 kB chunk warning (548 kB uncompressed in this fixture). No lazy-loading or throughput claims are made. `npm audit --omit=optional` reported no known vulnerabilities on the tested date.

## Create a dedicated Cloud fixture

Install and authenticate [clickhousectl](https://github.com/ClickHouse/clickhousectl), using API-key authentication for writes. See the [Managed Postgres documentation](https://clickhouse.com/docs/products/managed-postgres/). Use a dedicated disposable service because bootstrap changes database-wide PUBLIC grants. This tested shape is AWS `us-east-1`, `c6gd.large`, PostgreSQL 18, no HA; it incurs account compute/storage costs while retained. Confirm current available shapes and pricing before creating it.

```bash
umask 077
mkdir -p .local
export ORG_ID=your-organization-id
clickhousectl cloud postgres create --json --org-id "$ORG_ID" \
  --name collaborative-notes-demo --provider aws --region us-east-1 \
  --size c6gd.large --pg-version 18 --ha-type none > .local/create.json
export SERVICE_ID=$(python3 -c 'import json; print(json.load(open(".local/create.json"))["id"])')
clickhousectl cloud postgres get "$SERVICE_ID" --json --org-id "$ORG_ID" > .local/current.json
# Repeat get until current.json reports state "running"; then retrieve the CA.
clickhousectl cloud postgres certs get "$SERVICE_ID" --org-id "$ORG_ID" \
  --output .local/ca.pem
```

Creation JSON contains credentials; `get` does not return the password. Keep all these files private. Generate four private environment files with standard-library Python; no secrets belong in the client build:

```bash
python3 - <<'PY'
import json, secrets, shlex
from pathlib import Path
p = Path('.local')
d = json.loads((p / 'create.json').read_text())
base = dict(PGHOST=d['hostname'], PGPORT='5432', PGDATABASE='postgres',
            PGSSLMODE='verify-full', PGSSLROOTCERT=str((p / 'ca.pem').resolve()))
owner, runtime, token = [secrets.token_urlsafe(32) for _ in range(3)]
files = {
 'admin.env': dict(base, PGUSER=d['username'], PGPASSWORD=d['password'],
                   OWNER_PASSWORD=owner, RUNTIME_PASSWORD=runtime),
 'migration.env': dict(base, PGUSER='notes_owner', PGPASSWORD=owner),
 'runtime.env': dict(base, PGUSER='notes_runtime', PGPASSWORD=runtime, WORKSPACE_TOKEN=token),
 'test.env': dict(base, PGUSER='notes_runtime', PGPASSWORD=runtime, WORKSPACE_TOKEN=token,
                  OWNER_USER='notes_owner', OWNER_PASSWORD=owner,
                  ADMIN_USER=d['username'], ADMIN_PASSWORD=d['password']),
}
for name, env in files.items():
 f = p / name
 f.write_text(''.join(f'{k}={shlex.quote(v)}\n' for k, v in env.items()))
 f.chmod(0o600)
PY
```

## Bootstrap, migrate and seed

Use Bash and a PostgreSQL `psql` client. Environment files must be exported to child processes. Bootstrap runs once as administrator, migrations and seed as `notes_owner`, and the application as `notes_runtime`. There is no startup schema creation.

```bash
set -a; source .local/admin.env; set +a
psql -v ON_ERROR_STOP=1 -v owner_password="$OWNER_PASSWORD" \
  -v runtime_password="$RUNTIME_PASSWORD" -f sql/bootstrap.sql
set -a; source .local/migration.env; set +a
psql -v ON_ERROR_STOP=1 -f sql/001_up.sql
node dist-server/server/seed.js
psql -v ON_ERROR_STOP=1 -f sql/grants.sql
```

`seed` creates each original Yjs document once; repeating it preserves existing binary state. The reviewed `001_down.sql` removes all note data; use it only for a disposable migration lifecycle check, followed by up, seed and grants again. Up is deliberately a one-time migration, not an implicit schema repair. Runtime gets SELECT and column-level UPDATE for state/revision/time only. It cannot create tables or temporary tables, insert/delete notes, or edit titles. The shared runtime role is trusted: direct SQL can replace binary data without the API validators. There is no RLS or per-note user authorization.

## Run the local demo

Open a new terminal that has not sourced setup credentials, or use the clean environment below. Start the server with **only** runtime credentials. The server rejects any other `PGUSER`.

```bash
env -i HOME="$HOME" PATH="$PATH" bash --noprofile --norc -c '
  set -a; source .local/runtime.env; set +a
  node dist-server/server/main.js > .local/server.log 2>&1 &
  echo $! > .local/server.pid
'
# In another terminal, without database credentials:
npm run preview
```

Open `http://127.0.0.1:5173` in two browser windows and paste the private `WORKSPACE_TOKEN` into each password field. Do not paste it into a URL. Select a note, type and delete, then use **Work offline** and **Reconnect**. Reconnect before switching or leaving: switching destroys that tab's document and discards unsynchronized local edits.

Vite preview serves the built client and proxies `/collab` to the loopback WebSocket server. It is explicitly a local demo, not a production hosting configuration. The server validates the exact browser Origin and allowed Host before upgrade, then Hocuspocus authenticates the token and fixed document name. Load and mutation hooks preserve that document-scoped context. No wildcard CORS configuration or token-signing endpoint is provided.

## Storage invariants and limits

A store copies its captured binary update before awaiting, locks the row with `FOR UPDATE`, merges stored and incoming bytes with `Y.mergeUpdates`, validates, updates and commits using one pg client. Older/repeated snapshots cannot overwrite newer insertion/deletion history. An identical merged snapshot retains its revision and timestamp. The receipt identifies the captured update's SHA-256, not a promise that every tab's newest keystroke was included.

Incoming frames are limited to 64 KiB; complete stored CRDT state to 512 KiB; rendered text to 10,000 UTF-16 code units. Only the `content` text root is accepted: no rich-text attributes, embedded objects, disallowed controls or incomplete causal updates. Delete history also consumes binary space, so text below its limit can still hit the binary bound. The three fixed documents have at most 12 physical sockets, 32 queued messages per document, a four-connection pool and finite connect/SQL/lock waits. These are small-fixture bounds, not performance estimates.

The pinned Hocuspocus hooks debounce storage at 1.5 seconds with a five-second maximum debounce. Failure broadcasts an honest warning and keeps uncommitted changes in server memory. A subsequent edit can trigger another save; this implementation does not promise an automatic retry after a failed hook. Shutdown attempts native pending stores but has a 20-second deadline; neither browser disconnect nor graceful exit is presented as proof of commit. Observe a receipt or inspect committed state before a persistence demonstration.

## Reproduce acceptance

Tests use only synthetic documents in a dedicated fixture. `tests/cloud.mjs` and the Cloud browser controls require `test.env`, because failure triggers and row-lock controls use the owner role. Those credentials remain in the Node test process; Chromium receives only HOME/PATH/LANG. Install the native browser once:

```bash
npx playwright install --with-deps chromium
set -a; source .local/test.env; set +a
node tests/cloud.mjs
node tests/socket-controls.mjs
export EVIDENCE_DIR=/tmp/collaborative-notes-evidence
REQUIRE_CLOUD=1 node tests/browser.mjs
```

The Cloud storage helper covers insertion/deletion with reordered/repeated snapshots, independent competing row locks, a deferred COMMIT failure, role denials, actual-factory TLS failures and binary/allowlist bounds. The certificate negative removes trusted CA; the hostname negative calls Node `checkServerIdentity` with a substituted invalid hostname. Production uses the official CA and default hostname verification without a custom verifier. The pinned pg source sets the TLS connection host and DNS servername from `PGHOST`.

The browser helper opens two separate Chromium processes, checks simultaneous edits, deletes, offline/reconnect convergence, delayed and failed saves, subsequent recovery, desktop/mobile layout and empty browser storage. It writes the committed binary/text/revision/time snapshot and screenshots. Do not rerun on that same edited fixture expecting the marker-count assertions to remain one; use a fresh disposable migration and seed first.

Restart requires Linux `/proc`, Python 3, a direct server PID file from the run command and the browser helper's `committed-state.json`. The helper verifies the PID's application directory and command, waits for its actual exit, then starts a runtime-only replacement. Run from a fresh environment with runtime credentials, retaining the same evidence directory:

```bash
set -a; source .local/runtime.env; set +a
SERVER_PID_FILE="$PWD/.local/server.pid" \
RUNTIME_ENV_FILE="$PWD/.local/runtime.env" python3 tests/restart.py
node tests/restart-browser.mjs
```

Native protocol rejection controls can be run separately against their own memory-only test server, **with the real server stopped**: `node tests/gate-controls.mjs`. They demonstrate rejected invalid/oversized/incomplete updates leave unchanged bounded state and a valid same-note edit still proceeds. They are not Cloud durability evidence.

## Cleanup

Stop the local processes, then remove only your dedicated fixture:

```bash
kill "$(cat .local/server.pid)"
clickhousectl cloud postgres delete "$SERVICE_ID" --org-id "$ORG_ID"
clickhousectl cloud postgres list --org-id "$ORG_ID"
```

Verify your exact ID is absent. Keep private files out of Git; delete them according to your own credential-retention policy. The example's acceptance fixture was deleted after review, and its native VM was stopped and preserved.
