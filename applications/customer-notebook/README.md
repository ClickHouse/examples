# Customer notebook

A small Clojure workbench using ClickHouse Managed Postgres (public beta) for operational notes and ClickHouse for synthetic daily activity. Ring/Reitit serve forms, Hiccup escapes their contents, and next.jdbc uses pgJDBC/HikariCP for both query paths. Reports run through pg_clickhouse, with a separate connection pool and role.

This is a trusted local operator tool bound to 127.0.0.1, with seeded customers and native Ring CSRF protection. It has no signup, operator authentication, public deployment or tenant isolation. The runtime role can edit every seeded customer. Keep it on a trusted machine; sharing database credentials bypasses the form workflow.

An edit submits the revision the operator actually saw. One transaction conditionally updates the profile and appends an edit record on the same connection. Two editors cannot both save the same revision. A 409 retains the submitted note, health and original revision; reload and review the current profile before deciding what to save. An ambiguous connection failure requires reloading to check the revision. There is no automatic rebase or issue-token retry protocol.

The activity fixture is independent synthetic data, without CDC, ClickPipes or dual writes. Saving a note does not update ClickHouse, and a PostgreSQL transaction does not make a foreign read atomic with operational writes. A report failure displays unavailable; it does not invent zero activity. Empty days are filled with zero only after a successful query.

## Native prerequisites and dependencies

Use Linux, Java 21, Python 3, psql, jq, OpenSSL and the stable Clojure CLI. The verified run used Ubuntu 24.04 ARM64, OpenJDK 21.0.12.1, Clojure 1.12.6/CLI 1.12.6.1673, Ring 1.15.5, Reitit 0.11.0, Hiccup 2.0.0, next.jdbc 1.3.1118, pgJDBC 42.7.13 and HikariCP 7.1.0. PostgreSQL 18.6, pg_clickhouse 0.10.0 and ClickHouse 26.6.1.2191 were tested on 2 October 2026.

```bash
sudo apt-get update
sudo apt-get install -y openjdk-21-jdk-headless python3 python3-venv \
  postgresql-client jq openssl curl ca-certificates rlwrap
curl -fSLo install-clojure.sh \
  https://download.clojure.org/install/linux-install-1.12.6.1673.sh
echo '5ae63b082ed33bf4c29bf1a8317c5c15249d1bc753676b2f5177fb3804ad6f77  install-clojure.sh' | sha256sum -c -
bash install-clojure.sh --prefix "$HOME/.local"
export PATH="$HOME/.local/bin:$PATH"
git clone https://github.com/ClickHouse/examples.git
cd examples/applications/customer-notebook
clojure -Sdeps "$(cat deps-lock.edn)" -P -M:locked:build
clojure -Sdeps "$(cat deps-lock.edn)" -M:locked:build
clojure -Sdeps "$(cat deps-lock.edn)" -M:locked:test
```

The official installer also verifies its downloaded tools archive SHA256. `deps.edn` pins direct dependencies; `deps-lock.edn` is a Clojure CLI `:locked` alias overriding all 51 resolved Maven versions. Pass it with `-Sdeps` as shown. The native preflight and locked graphs agreed exactly. Build/tests need no database secrets. A fresh source directory passed four unit tests / 29 assertions.

## Create the owned Postgres service

Install [clickhousectl](https://github.com/ClickHouse/clickhousectl), authenticate with your Cloud API key in a private terminal, and choose your organization. These services incur Cloud charges; the example has no HA requirement. The tested small PG shape is c6gd.large in AWS us-east-1. Check current size availability before creating a retained deployment.

```bash
curl -fsSL https://clickhouse.com/cli | sh
export PATH="$HOME/.local/bin:$PATH"
clickhousectl cloud auth login --interactive
umask 077
mkdir -p .deployment
export CH_ORG_ID=YOUR_ORG_ID
clickhousectl cloud postgres create --org-id "$CH_ORG_ID" \
  --name customer-notebook-pg --provider aws --region us-east-1 \
  --size c6gd.large --pg-version 18 --ha-type none --json \
  > .deployment/postgres-create.json
export PG_ID=$(jq -r .id .deployment/postgres-create.json)
clickhousectl cloud postgres get "$PG_ID" --org-id "$CH_ORG_ID" --json \
  > .deployment/postgres-status.json
jq -r .state .deployment/postgres-status.json
```

Repeat the final get until running, with a bounded provisioning window; preserve the ID instead of creating another service after a timeout. Create returns the administrator password once. Get does not return it.

```bash
clickhousectl cloud postgres certs get "$PG_ID" --org-id "$CH_ORG_ID" \
  --output "$PWD/.deployment/ca.pem"
jq -r '"export PGHOST="+(.hostname|@sh),
       "export PGPORT=5432", "export PGDATABASE=postgres",
       "export PGUSER="+(.username|@sh), "export PGPASSWORD="+(.password|@sh)' \
  .deployment/postgres-create.json > .deployment/admin.env
printf 'export PGSSLROOTCERT=%q\n' "$PWD/.deployment/ca.pem" >> .deployment/admin.env
printf 'export PGSSLMODE=verify-full\nexport PGCONNECT_TIMEOUT=5\n' >> .deployment/admin.env
source .deployment/admin.env
psql -X -v ON_ERROR_STOP=1 -c "SELECT version(); SELECT name,default_version FROM pg_available_extensions WHERE name='pg_clickhouse';"
psql -X -v ON_ERROR_STOP=1 -c 'CREATE SCHEMA notebook_fdw; CREATE EXTENSION pg_clickhouse WITH SCHEMA notebook_fdw; SELECT notebook_fdw.pgch_version();'
```

Stop if the extension/version or secure server options do not match your deployment. The [extension reference](https://clickhouse.com/docs/products/managed-postgres/extensions/pg_clickhouse/reference) can describe newer behavior than the installed library.

## Establish a narrow analytical network route

Use a supported documented outbound address, or observe this fixture's actual route before configuring ClickHouse. The inbound Postgres hostname is not evidence of its egress identity. This verified 0.10.0 fixture used the owner-only deprecated HTTP helper once to a public IPv4 echo endpoint, sending only `SELECT 1` and no real credentials/customer data. Its installed HTTP resolver uses TLS on port 443; libcurl retains system certificate/name verification. This setup probe is not a runtime API and may disappear in later versions.

```bash
export PG_EGRESS_IP=$(psql -X -At -v ON_ERROR_STOP=1 -c \
  "SELECT notebook_fdw.clickhouse_raw_query('SELECT 1','driver=http host=ipv4.icanhazip.com port=443');")
export APP_EGRESS_IP=$(curl -4fsS --max-time 10 https://icanhazip.com)
export PG_EGRESS_CIDR=$(python3 -c 'import os,ipaddress; print(str(ipaddress.IPv4Address(os.environ["PG_EGRESS_IP"]))+"/32")')
export APP_EGRESS_CIDR=$(python3 -c 'import os,ipaddress; print(str(ipaddress.IPv4Address(os.environ["APP_EGRESS_IP"]))+"/32")')
clickhousectl cloud service create --org-id "$CH_ORG_ID" \
  --name customer-notebook-ch --provider aws --region us-east-1 \
  --min-replica-memory-gb 8 --max-replica-memory-gb 8 --num-replicas 2 \
  --idle-scaling true --idle-timeout-minutes 5 \
  --ip-allow "$PG_EGRESS_CIDR=observed-postgres" \
  --ip-allow "$APP_EGRESS_CIDR=setup-client" --json > .deployment/clickhouse-create.json
export CH_ID=$(jq -r .service.id .deployment/clickhouse-create.json)
clickhousectl cloud service get "$CH_ID" --org-id "$CH_ORG_ID" --json \
  > .deployment/clickhouse-status.json
jq -r .state .deployment/clickhouse-status.json
```

The current CLI requires at least two replicas for a first warehouse; this fixture uses its minimum 8 GiB memory per replica. Wait for running. Observed egress is fixture-specific and can change after infrastructure changes; re-verify it, rather than opening unrestricted access. If this route cannot be verified, stop and clean up. The actual secure binary query below is the final route control.

```bash
jq -r '.service.endpoints[]|select(.protocol=="https")|
       "export CH_HOST="+(.host|@sh),"export CH_PORT="+(.port|tostring|@sh)' \
  .deployment/clickhouse-create.json > .deployment/analytics.env
jq -r '"export CH_ADMIN_PASSWORD="+(.password|@sh)' \
  .deployment/clickhouse-create.json >> .deployment/analytics.env
python3 - <<'PY'
import pathlib,secrets,shlex
names=['NOTEBOOK_MIGRATOR_PASSWORD','NOTEBOOK_APP_PASSWORD',
       'NOTEBOOK_REPORT_PASSWORD','CH_REPORT_PASSWORD']
pathlib.Path('.deployment/passwords.env').write_text(''.join(
    'export '+name+'='+shlex.quote('Aa1!'+secrets.token_hex(30))+'\n' for name in names))
PY
source .deployment/analytics.env
source .deployment/passwords.env
python3 scripts/seed-analytics.py
python3 scripts/seed-analytics.py
```

Seed explicitly truncates and replaces the four-row synthetic fixture, using one synchronous insert with retry deduplication disabled. Repeating it leaves exactly four events. This is a small setup fixture, not a production ingestion pattern; do not run it against retained production data. Runtime has no ClickHouse write credentials. No Query API keys are created by these direct HTTPS commands.

## Operational migrations and foreign table

```bash
psql -X -v migrator_password="$NOTEBOOK_MIGRATOR_PASSWORD" \
  -v app_password="$NOTEBOOK_APP_PASSWORD" -v report_password="$NOTEBOOK_REPORT_PASSWORD" \
  -f sql/bootstrap.sql
PGUSER=notebook_migrator PGPASSWORD="$NOTEBOOK_MIGRATOR_PASSWORD" psql -X -f sql/migrate-up.sql
PGUSER=notebook_migrator PGPASSWORD="$NOTEBOOK_MIGRATOR_PASSWORD" psql -X -f sql/seed.sql
psql -X -v ch_host="$CH_HOST" -v ch_password="$CH_REPORT_PASSWORD" -f sql/foreign-table.sql
```

Bootstrap is once per empty role/schema fixture. Migrate-up is transactional and repeats as a no-op, guarded by an advisory lock and version table. Migrate-down is `psql -f sql/migrate-down.sql` under the same migrator credentials; it removes profiles/history. Repeated operational seed preserves edits. The NOLOGIN owner is assumed only for schema/seed operations. Administrator-only extension/server/mapping setup grants the report role SELECT on this one foreign table; arbitrary-query helpers remain denied.

The remote login has only SELECT on the activity table, with readonly 2 so the driver can set query settings. The installed defaults `join_use_nulls 1,group_by_use_nulls 1,final 1,transform_null_in 0` are retained alongside execution/read/result limits. Our plain MergeTree fixture needs no version selection or tombstone logic. The mapped Postgres role can see its own mapping options, including the remote password, through `pg_user_mappings`; credentials are not hidden from that trusted role. The operational role cannot use this schema.

## Start and use the workbench

Create a runtime file containing only endpoint/CA fields and the two restricted Postgres passwords:

```bash
python3 - <<'PY'
import os,pathlib,shlex
names=['PGHOST','PGPORT','PGDATABASE','PGSSLROOTCERT',
       'NOTEBOOK_APP_PASSWORD','NOTEBOOK_REPORT_PASSWORD']
pathlib.Path('.deployment/app.env').write_text(''.join(
    'export '+name+'='+shlex.quote(os.environ[name])+'\n' for name in names))
PY
```

Open a new terminal that has not sourced setup credentials before loading this file. A nested shell inherits the administrator/migrator/analytical secrets exported during setup.

```bash
source .deployment/app.env
clojure -Sdeps "$(cat deps-lock.edn)" -M:locked:run
```

Open http://127.0.0.1:8080, choose Northstar Labs, edit its note/health, and save. Open the same profile in two tabs before saving to see stale-edit feedback. View September 28–30, 2026 activity: counts 2, 0, 1. Harbor Studio has 0, 1, 0; Fieldcraft Tools has all zeroes.

The report accepts 1–31 inclusive UTC dates within 2000-01-01..2100-12-31. It binds UUID/LocalDate parameters and projects SQL dates as text before decoding, avoiding process-timezone shifts. Customer list/history are capped at 20 each; note is at most 2,000 UTF-16 units and form body 4 KiB. Unknown fields, long decimal revisions, NUL/controls/unpaired surrogates and malformed percent-encoded UTF-8 are rejected. Hiccup escapes note contents, and forms retain Ring CSRF protection.

Hikari pools have two operational connections and one reporting connection; acquisition 3 s, connect 5 s and socket 15 s. Role settings are operational statement 5 s / lock 2 s and report statement 12 s / lock 2 s. Remote query execution 10 s / read 20,000 rows / result 31 rows / 64 KiB are bounded separately. These layer limits are not one overall deadline. An idle analytical service may fail a first report while resuming; retry the report, and continue saving notes. For a bounded acceptance window, use `clickhousectl cloud service scale "$CH_ID" --org-id "$CH_ORG_ID" --idle-scaling false`; restore idle scaling or delete promptly afterward.

## Verify and clean up

In a separate test shell, explicitly load `.deployment/admin.env`, `.deployment/passwords.env`, `.deployment/analytics.env` and `.deployment/app.env`. Runtime should still use only its original app file.

```bash
clojure -Sdeps "$(cat deps-lock.edn)" -M:locked:security
clojure -Sdeps "$(cat deps-lock.edn)" -M:locked:plan
python3 checks/cloud.py
python3 -m venv .deployment/browser
.deployment/browser/bin/pip install -r checks/requirements.txt
.deployment/browser/bin/python -m playwright install --with-deps chromium
export EVIDENCE_DIR="$PWD/.deployment/evidence"
.deployment/browser/bin/python checks/browser.py
```

`checks/launch.py` starts a runtime-only child and records its PID in EVIDENCE_DIR. Use it instead of the foreground run command if exercising `checks/restart.py`; the helper asserts the original PID is gone before starting another. Its children use Pacific/Auckland to exercise date boundaries. CSRF sessions are in memory and reset on restart; profiles and edit history persist. `:tls-probe` can exercise the same runtime pool factory with an unrelated valid PEM (`EXPECTED_TLS_FAILURE=ca`) or the same endpoint's IP (`EXPECTED_TLS_FAILURE=hostname`) while retaining verify-full.

Verified live controls: two independent HTTP editors 303/409, rollback after profile UPDATE when append fails, retained escaped stale form, actual Chromium CSRF 403, invalid input 400 / body 413, exact three-customer app/direct report equality including empty days, remote permission loss with successful operational edit and report recovery, actual process restart, real Hikari role/settings/TLS controls and remote INSERT denial. EXPLAIN of the exact bound report pushed projection cast, customer/date filters, aggregation, sort and limit to ClickHouse. No scale/performance claim follows from this tiny fixture.

Stop the app first. If retaining services, any schema cleanup must use administrator credentials explicitly (`source .deployment/admin.env`), then drop only this app's server/schemas/roles. Delete your owned test resources when finished:

```bash
clickhousectl cloud postgres delete "$PG_ID" --org-id "$CH_ORG_ID"
clickhousectl cloud service delete "$CH_ID" --org-id "$CH_ORG_ID" --force
clickhousectl cloud postgres list --org-id "$CH_ORG_ID" --json
clickhousectl cloud service list --org-id "$CH_ORG_ID" --json
```

Confirm both IDs are absent. Analytical `--force` stops/polls/deletes a running service; Postgres delete has no force flag. Preserve source/evidence and remove private credentials from retained public copies.

Primary references: [next.jdbc transactions](https://github.com/seancorfield/next-jdbc/blob/develop/doc/transactions.md), [pgJDBC TLS](https://jdbc.postgresql.org/documentation/ssl/), [pg_clickhouse 0.10.0 reference](https://github.com/ClickHouse/pg_clickhouse/blob/v0.10.0/doc/pg_clickhouse.md), [Managed Postgres overview](https://clickhouse.com/docs/products/managed-postgres/overview).
