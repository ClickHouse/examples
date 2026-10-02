# Inspection log

A small Sinatra workbench for recording complete inspections of three synthetic assets in [ClickHouse Managed Postgres (public beta)](https://clickhouse.com/docs/products/managed-postgres/overview). Choose an asset, calendar day, outcome, three checklist results and a short note. Save once, view immutable records, filter asset history, and download a bounded CSV.

This is a trusted **loopback-only** sample. There is no operator identity, authentication or tenant isolation. Cookie sessions contain CSRF state. The shared database role covers every fixture asset; it is trusted server configuration. The app does not integrate with live equipment.

## Transaction and retry behavior

[`Store#save`](lib/store.rb) uses one explicit Sequel transaction. It locks the single seeded fixture-budget row, looks up the retained request UUID, then increments the budget and inserts the inspection header plus its three named checklist results. An exact canonical retry returns the original inspection. Reusing the UUID with different content returns 409 and preserves the submitted fields. Replay lookup precedes the 200-record capacity check, so a saved form can still replay at capacity.

The canonical digest includes asset, Date, outcome, ordered housing/cable/label results and note. UUID spelling is normalized to lowercase. CRLF and CR normalize to LF in the stored note and digest; other note whitespace is retained. CSRF tokens are excluded from the digest. A lost acknowledgment may be retried with the same UUID and fields. Keep that UUID; changing it can create a second record. Validation 422, conflict 409, capacity 409 and database 503 pages retain safe submitted fields. Invalid UTF-8/control text gets 400 without echoing it.

The budget lock intentionally serializes saves across all assets. It avoids a racing pre-count and is suitable for this small fixture. Header IDs are bounded 1–200 by a database check, request UUIDs are unique, and budget usage cannot exceed 200. A transaction failure restores the budget, header and children together. There is no edit/delete route or expiry of retry keys.

Calendar days remain Ruby `Date` / PostgreSQL `DATE` and serialize with `iso8601`; they never pass through a midnight timestamp. Supported days are 2000-01-01 through 2100-12-31. History shows at most 25 rows ordered by day descending, then numeric ID descending. CSV includes at most 100 rows ordered by day ascending, then numeric ID ascending, across at most 31 inclusive calendar days. An oversized CSV gets 422 asking for narrower filters, rather than a truncated download. Rows are loaded before CSV generation so a slow download holds no pool checkout.

Ruby CSV handles commas, quotes and newlines. Text in asset/note cells that starts with a formula-looking prefix (including leading whitespace) or a tab/newline receives a leading apostrophe. This **changes exported text** and reduces a defined formula risk; it is not a guarantee across every spreadsheet/import workflow. Review exports for the intended importer. See [OWASP's CSV injection discussion](https://community.owasp.org/attacks/CSV_Injection).

## Native Linux setup

Verified on Ubuntu 24.04 ARM 64 on 2 October 2026: Ruby 4.0.7, Bundler 4.0.22, Sinatra 4.2.1, Sequel 5.109.0, pg 1.7.0 / native libpq 16.15, Puma 8.0.2, Rack 3.2.7, rack-session 2.1.2, rack-protection 4.2.1, ERB 6.0.7 and CSV 3.3.6. The owned Cloud fixture ran PostgreSQL 18.6. `Gemfile.lock` pins transitive releases and gem checksums; only Linux ARM 64 was tested. The pg gem is deliberately compiled from source against libpq.

Build in a native Linux directory, not a shared host mount:

```bash
sudo apt-get update
sudo apt-get install -y build-essential autoconf bison pkg-config libssl-dev \
  libyaml-dev libreadline-dev zlib1g-dev libffi-dev libgmp-dev libpq-dev \
  libncurses-dev libgdbm-dev curl ca-certificates postgresql-client python3 jq
mkdir -p "$HOME/toolchains"
cd "$HOME/toolchains"
curl -fsSLo ruby-4.0.7.tar.gz https://cache.ruby-lang.org/pub/ruby/4.0/ruby-4.0.7.tar.gz
echo '911ace20f90d068ca0e4dda6d0e4f0f81e52e52f2dd4f4004c721e253412e82d  ruby-4.0.7.tar.gz' | sha256sum --check
tar -xzf ruby-4.0.7.tar.gz
cd ruby-4.0.7
./configure --prefix="$HOME/.local/ruby-4.0.7" --disable-install-doc --disable-yjit --disable-zjit
make -j2
make install
export PATH="$HOME/.local/ruby-4.0.7/bin:$PATH"
gem install bundler --version 4.0.22 --no-document
cd /absolute/native/path/to/examples/applications/inspection-log
bundle _4.0.22_ config set --local path "$HOME/.local/inspection-bundle"
bundle _4.0.22_ config set --local frozen true
bundle _4.0.22_ install
bin/check
```

The archive checksum comes from the [official Ruby downloads page](https://www.ruby-lang.org/en/downloads/). `bin/check` needs no database credentials: it checks Ruby syntax, compiles ERB in a rendering method context, and runs 5 tests / 50 assertions for validation, raw form boundaries and parsed CSV. CI performs the same native build/frozen install on Ubuntu ARM 64.

## Create the owned Cloud fixture

Install and authenticate [clickhousectl](https://clickhouse.com/blog/getting-started-clickhousectl). These commands use its 0.5.0 syntax and an explicit organization. Save create output privately: it returns the administrator password once; subsequent `get` does not.

```bash
mkdir -p "$HOME/inspection-private"
chmod 700 "$HOME/inspection-private"
export INSPECTION_ORG_ID='YOUR_ORG_ID'
clickhousectl cloud postgres create --json --org-id "$INSPECTION_ORG_ID" \
  --name inspection-log-example --provider aws --region us-east-1 \
  --size c6gd.large --pg-version 18 --ha-type none \
  > "$HOME/inspection-private/create.json"
chmod 600 "$HOME/inspection-private/create.json"
export INSPECTION_PG_ID=$(jq -r '.id' "$HOME/inspection-private/create.json")
clickhousectl cloud postgres get "$INSPECTION_PG_ID" --org-id "$INSPECTION_ORG_ID"
```

Repeat `get` until `state` is `running`, then retrieve the Cloud CA:

```bash
clickhousectl cloud postgres certs get "$INSPECTION_PG_ID" \
  --org-id "$INSPECTION_ORG_ID" --output "$HOME/inspection-private/ca.pem"
```

This is a billable no-HA fixture. Delete it after the exercise; stopping the local app does not delete its database.

## Bootstrap, migrate and seed

In a setup terminal, export administrator connection fields from the private receipt and generate independent role/session secrets. Do not print those values:

```bash
export PGHOST=$(jq -r '.hostname' "$HOME/inspection-private/create.json")
export PGPORT=5432 PGDATABASE=postgres
export PGUSER=$(jq -r '.username' "$HOME/inspection-private/create.json")
export PGPASSWORD=$(jq -r '.password' "$HOME/inspection-private/create.json")
export PGSSLMODE=verify-full PGCONNECT_TIMEOUT=5
export PGSSLROOTCERT="$HOME/inspection-private/ca.pem"
python3 - <<'PY'
from pathlib import Path
import os, secrets
path = Path.home() / 'inspection-private/passwords.env'
path.write_text('MIGRATOR_PASSWORD=Aa1' + secrets.token_hex(24) + '\n'
                'APP_PASSWORD=Aa1' + secrets.token_hex(24) + '\n'
                'SESSION_SECRET=' + secrets.token_hex(64) + '\n')
path.chmod(0o600)
PY
set -a
source "$HOME/inspection-private/passwords.env"
set +a
psql -X -v ON_ERROR_STOP=1 -v migrator_password="$MIGRATOR_PASSWORD" \
  -v app_password="$APP_PASSWORD" -f sql/bootstrap.sql
bin/migrate
psql -X -v ON_ERROR_STOP=1 -f sql/seed.sql
```

`bin/migrate` uses the separate `inspection_migrator` login and assumes the non-login `inspection_owner` role on its single connection. It uses the same verified TLS configuration as runtime. Repeat migration stays at version 1; repeat seed creates no extra assets/budget. `bin/migrate 0` drops this app's tables and data; use it only on a disposable fixture before migrating and seeding again.

The runtime has select on assets/budget/header/children, insert on header/children, and update only on the budget's `used` column. It cannot alter/delete history, edit assets, create schema objects/TEMP tables, or assume the owner role. The three-child completeness invariant belongs to the application transaction; a trusted owner or leaked runtime credential can bypass application validation. There is no row-level tenant boundary.

Write a runtime-only file from the setup terminal:

```bash
python3 - <<'PY'
from pathlib import Path
import os
values = {key: os.environ[key] for key in ('PGHOST', 'PGPORT', 'PGDATABASE', 'PGSSLROOTCERT')}
values.update(PGPASSWORD=os.environ['APP_PASSWORD'], SESSION_SECRET=os.environ['SESSION_SECRET'], TZ='Pacific/Honolulu')
path = Path.home() / 'inspection-private/app.env'
path.write_text(''.join(key + '=' + value + '\n' for key, value in values.items()))
path.chmod(0o600)
PY
```

## Run the protected form

Open a new terminal that has not sourced setup credentials. Set the Ruby path, change to the app directory and start with the runtime file:

```bash
export PATH="$HOME/.local/ruby-4.0.7/bin:$PATH"
cd /absolute/native/path/to/examples/applications/inspection-log
python3 checks/launch.py "$HOME/inspection-private/app.env"
```

The launcher passes only runtime fields and basic process settings to Puma; inherited administrator/migrator variables are excluded. Visit `http://127.0.0.1:9292/`, choose an asset/day/checklist, save, then follow **View asset history** and **Download CSV**.

Puma binds 127.0.0.1 with 4 threads and no worker processes. Sequel permits 4 connections, a 3-second pool-acquisition wait and 5-second connection timeout. Each connection sets 8-second statement,3-second lock and 10-second idle-transaction timeouts. These are layer limits, not an end-to-end HTTP deadline. Sequel's [pg_auto_parameterize extension](https://sequel.jeremyevans.net/rdoc-plugins/files/lib/sequel/extensions/pg_auto_parameterize_rb.html) binds values in runtime dataset SQL. Fixed setup SQL contains no untrusted fragments.

Sequel's pg adapter uses `sslmode: verify-full` and the downloaded `sslrootcert`; there is no insecure fallback. [Sequel documents adapter/pool configuration](https://sequel.jeremyevans.net/rdoc/files/doc/opening_databases_rdoc.html) and [transaction behavior](https://sequel.jeremyevans.net/rdoc/files/doc/transactions_rdoc.html).

The app keeps Sinatra protection enabled and uses Rack's masked authenticity tokens with a private cookie-session secret. Exact allowed Host values are localhost/127.0.0.1; POST requires the matching HTTP loopback Origin. Cookies are HttpOnly/SameSite Strict and deliberately not Secure on local HTTP. This configuration is not a public deployment recipe. URL-encoded saves are capped at 32 KiB before parsing; duplicate decoded field names return 400. Empty `&` separators are ignored. Unknown fields/enums, dates, checklist results and note bounds are validated before SQL. ERB escapes displayed asset/note/field text.

## Reproduce Cloud acceptance

The `checks/` helpers use a disposable Cloud fixture and create synthetic data. They do not need CI credentials. Install browser tooling separately from the app bundle in the VM:

```bash
python3 -m venv "$HOME/inspection-private/browser"
"$HOME/inspection-private/browser/bin/pip" install playwright==1.63.0
"$HOME/inspection-private/browser/bin/python" -m playwright install --with-deps chromium
export EVIDENCE_DIR="$HOME/inspection-private"
"$HOME/inspection-private/browser/bin/python" checks/browser.py
```

Run the browser helper exactly once on the empty seeded fixture: it creates record 1, checks escaping/non-UTC DATE and parses CSV. Then, in a separate **test setup** terminal, explicitly load administrator PG* fields as above and export `APP_PASSWORD` from `passwords.env`. With the app still running:

```bash
set -a
source "$HOME/inspection-private/passwords.env"
set +a
python3 checks/cloud.py
```

The helper checks native middleware, two independent session retries, conflicting fields, an owner-installed second-child fault with cleanup in `finally`, runtime grant/check failures and last-slot contention. It deliberately fills the fixture to 200 records. Its final CSV/history assertions can also run read-only as `python3 checks/cloud.py --reports-only`; this does not reset or rerun mutations.

For the genuine process restart, record the **actual Puma PID** in a private file (a background `python3 checks/launch.py ...` retains its PID through exec). Keep the admin/test variables in the test terminal to verify the launcher excludes them:

```bash
export RUNTIME_ENV="$HOME/inspection-private/app.env"
export SERVER_PID_FILE="$HOME/inspection-private/server.pid"
export EVIDENCE_DIR="$HOME/inspection-private"
python3 checks/security_restart.py
"$HOME/inspection-private/browser/bin/python" checks/mobile.py
```

`security_restart.py` checks the actual `Database.connect` path against the correct endpoint, an untrusted CA and an IP/name mismatch. It signals only the recorded Puma PID, asserts that process has disappeared before starting the replacement, then compares persisted asset/note/day/time/request fields and exact CSV. It also replays record 1's uppercase UUID at capacity. The helpers expect the stated browser fixture; keep failed attempts distinct from passing results.

Observed on 2 October 2026: fresh frozen bundle;5 tests / 50 assertions; migration 1/repeat 1/down 0/up 1 and repeated seed; actual browser desktop/mobile; protected HTTP boundaries; concurrent retained requests with one debit; post-header/first-child rollback; cap 200 with 600 children; CSV overflow 422 / exact 100 rows; history 25 numeric ordering; actual runtime 42501/23514/23505; CA/name negatives through Sequel; real Puma 18797→19032 with original gone, exact persisted content/CSV and retained replay. These are bounded correctness checks, not a load benchmark.

## Cleanup

Stop the recorded Puma process, then delete only the service you created:

```bash
kill "$(cat "$HOME/inspection-private/server.pid")"
clickhousectl cloud postgres delete "$INSPECTION_PG_ID" --org-id "$INSPECTION_ORG_ID"
clickhousectl cloud postgres list --org-id "$INSPECTION_ORG_ID"
```

Confirm its ID is absent, allowing for asynchronous deletion. Postgres deletion accepts a running service and has no `--force` flag. It removes the fixture permanently. Remove private credential/receipt files when no longer needed. The review run's owned service was deleted after acceptance.
