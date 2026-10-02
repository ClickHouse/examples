# CSV review desk

Stage a CSV, correct its invalid rows, and approve the complete batch into a catalogue backed by [ClickHouse Managed Postgres (public beta)](https://clickhouse.com/docs/products/managed-postgres/overview). This small Streamlit workbench uses SQLAlchemy, psycopg, Alembic and pandas. Invalid values and their feedback remain durable, so closing the browser does not lose a review.

Two views cover the workflow: upload/list saved batches, then review a batch in a fixed-row data editor. Approval inserts new catalogue items; it never updates an existing SKU. This is a trusted local workbench bound to loopback, without application authentication. Anyone who can reach the process has the same operator authority. Public deployment requires an authentication boundary and appropriate HTTPS/proxy configuration; it is outside this example's tested scope.

## The rules

- UTF-8 CSV, **no BOM**, exactly `sku,name,price_cents` in that order. CSV quoting and CRLF/LF are supported. Blank records, extra/missing fields and malformed quoting are rejected.
- Upload **1–262,144 bytes**, **1–200 records**. The raw staging limits are SKU 80, name 240 and price 32 characters, no NUL; exceeding these is a rejected upload/save. Values inside those raw limits can be invalid and corrected later.
- Valid SKU: 1–40 ASCII uppercase letters/digits/underscore/hyphen, beginning with letter/digit. Valid name:1–120 characters, no surrounding whitespace or Unicode control characters (`Cc`). Valid price: decimal integer text **0–1,000,000,000 cents**, no signs, fractional values, exponent notation or leading zeros. Prices are converted to integers only after validation. Currency is not inferred; these are catalogue minor-unit integers.
- Every staged row gets a server-generated UUID and fixed ordinal. The editor hides/disables the UUID; the server independently requires the exact original identity set. Rows cannot be added, removed or moved between batches.
- Save and approval lock the parent batch. Every pending write requires the revision the caller reviewed. A stale write is rejected; saving increments the revision. Reads take a short parent shared lock so header/revision and rows agree.
- Approval validates the saved rows and catalogue again, inserts all items, and marks the batch approved in one transaction. A unique SKU constraint catches a conflict that appears after validation; the entire publication rolls back. Repeating successful approval returns the original time/count even with the original revision.
- Invalid approval commits refreshed validation feedback and an increased revision, with zero items published. After a late constraint conflict, refresh/save to update validation against the winner. Approved batches/rows cannot be edited; triggers guard them and a composite foreign key binds catalogue provenance to the same batch and row.

The UI re-reads after each write. Only the thread-safe SQLAlchemy engine/pool is shared through `st.cache_resource`; ORM Sessions and query results are not cached. If another session changes the revision, the UI discards old editor state, announces the refresh and suppresses Save/Approve for that rerun. Review the refreshed rows and click again. Unsaved local edits are not durable until saved.

## 1. Install inside Linux

Verified with Ubuntu 24.04 arm 64/Python 3.12. The exact tested package versions are in `requirements.in` and all runtime transitive dependencies are pinned in `requirements.txt`. Run the following from this application's directory, in a native Linux filesystem:

```sh
sudo apt-get update
sudo apt-get install -y --no-install-recommends python3-venv postgresql-client git curl jq openssl
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
python -m pip check
```

Clone the examples repository if needed and enter `applications/csv-review-desk`. No Node/frontend build is required. `samples/valid.csv` and `samples/needs-review.csv` contain synthetic records; the second needs price/name/duplicate-SKU corrections. Uploaded strings, including formula-looking names, remain literal text. This app never executes formulas or fetches uploaded URLs.

## 2. Create your own Cloud service

Install [clickhousectl](https://clickhouse.com/blog/clickhousectl-v0-2-0-postgres-clickpipes-more) and authenticate using an Admin API key from your Cloud organization. Use interactive sign-in so credentials are not shell-history arguments:

```sh
curl -fsSL https://clickhouse.com/cli | sh
export PATH="$HOME/.local/bin:$PATH"
clickhousectl cloud auth login --interactive
clickhousectl cloud auth status
clickhousectl cloud org list
umask 077
mkdir -p .deployment
```

Create private `.deployment/resources.env` with your organization, available region/size and the direct connection fields supplied after creation:

```dotenv
CH_ORG_ID=YOUR_ORGANIZATION_UUID
CLOUD_REGION=us-east-1
PG_SIZE=c6gd.large
```

The tested fixture used AWS us-east-1, `c6gd.large`, Postgres 18 and no HA. Check current availability and [pricing](https://clickhouse.com/pricing) before creation. Compute/storage can incur charges; stopping Streamlit does not stop database billing.

```sh
source .deployment/resources.env
clickhousectl cloud postgres create --org-id "$CH_ORG_ID" \
  --name csv-review-desk-example --provider aws --region "$CLOUD_REGION" \
  --size "$PG_SIZE" --pg-version 18 --ha-type none --json \
  > .deployment/postgres-create.json
PG_SERVICE_ID="$(jq -er '.id' .deployment/postgres-create.json)"
```

Save `PG_SERVICE_ID` in `resources.env`. The receipt contains the initial password once. Preserve it privately; `get` does not return passwords. If creation is interrupted, inspect the list before retrying to avoid duplicate billable services. Repeat `get`, not `create`, until state is `running`:

```sh
clickhousectl cloud postgres get "$PG_SERVICE_ID" --org-id "$CH_ORG_ID" --json
clickhousectl cloud postgres certs get "$PG_SERVICE_ID" --org-id "$CH_ORG_ID" \
  --output .deployment/postgres-ca.pem
```

Append `PGHOST=YOUR_DIRECT_HOSTNAME`, `PGPORT=5432`, `PGDATABASE=postgres`, `PGADMIN=postgres` and `PGSSLROOTCERT=/ABSOLUTE/PATH/TO/postgres-ca.pem` to `resources.env`, using actual returned values. Use the direct endpoint for schema work. The CA path must exist in the Linux environment running Python.

## 3. Separate schema and runtime roles

Generate passwords once, preserving the file on retries:

```sh
cat > .deployment/passwords.env <<PASSWORDS
PG_MIGRATION_PASSWORD=Aa1_$(openssl rand -hex 24)
PG_APP_PASSWORD=Aa1_$(openssl rand -hex 24)
PASSWORDS
source .deployment/resources.env
source .deployment/passwords.env
export PGHOST PGPORT PGDATABASE PGSSLROOTCERT
export PGSSLMODE=verify-full
export PG_MIGRATION_PASSWORD PG_APP_PASSWORD
export PGPASSWORD="$(jq -er '.password' .deployment/postgres-create.json)"
psql -X -v ON_ERROR_STOP=1 -U "$PGADMIN" -f sql/bootstrap.sql
unset PGPASSWORD
```

The bootstrap creates `csv_review` owned by `csv_migrator` and the restricted `csv_app` login. It revokes public schema/database CREATE for this dedicated service; do not run it on an unrelated database. It intentionally fails rather than silently replacing an existing role/schema.

Run migrations and grants in a separate subshell:

```sh
(
  export PGUSER=csv_migrator PGPASSWORD="$PG_MIGRATION_PASSWORD"
  alembic upgrade head
  psql -X -v ON_ERROR_STOP=1 -f sql/grants.sql
)
```

Native Alembic records the migration in `csv_review.alembic_version`. To check up/down/up on an empty development fixture, run `alembic downgrade base` then `alembic upgrade head` **before grants or uploaded records**; downgrade destroys the domain tables. For future schema changes, add/review a new migration and review runtime grants. Do not edit an applied migration.

Runtime can read/insert/update batches and staged rows, and read/insert catalogue items. It cannot alter schema/migration history or update/delete catalogue items. Shared runtime credentials are trusted: these grants do not create per-person or per-tenant isolation, and direct writes can still violate assumptions outside the protected constraints. All operators see the same catalogue.

## 4. Start the local workbench

Copy `.env.example` to `.env` and fill in the direct host, database, CA path and **runtime** password. No connection string parsing is needed: SQLAlchemy builds its URL safely from separate fields. `make_engine` hardcodes `sslmode=verify-full`, passing the Cloud CA to psycopg to verify both certificate and hostname. Do not weaken TLS to resolve readiness/certificate errors.

Start from a fresh shell with only runtime fields exported:

```sh
source .venv/bin/activate
set -a
source .env
set +a
streamlit run app.py
```

Open [localhost:8501](http://localhost:8501). Native XSRF/CORS protections remain enabled; neither is disabled in configuration. Upload `samples/needs-review.csv`, correct all three issue types, save, inspect the committed feedback, then approve. Reopening its URL shows the same immutable approved rows. Re-uploading those SKUs creates a reviewable conflict, not an overwrite.

The pool allows four connections, with no overflow, certificate/connect checks,15-second statement and 10-second lock timeouts. Batch lists show 20 per page; complete batch review is bounded by 200 rows. Database failure produces a friendly UI error. This is not a claim that every possible outage stops further connection attempts.

## Checks

```sh
python -m unittest discover -s tests -p 'test_*.py' -v
python -m compileall -q app.py reviewdesk migrations tests
```

Development tooling and browser dependencies are separately pinned in `requirements-dev.txt`:

```sh
python -m pip install -r requirements-dev.txt
ruff check .
ruff format --check .
python -m playwright install --with-deps chromium
```

Run real acceptance only on this dedicated disposable Cloud service. `TEST_MIGRATOR_PASSWORD` gives the **test process alone** authority to remove its own UUID-labelled fixtures; never export it to the Streamlit server:

```sh
(
  export TEST_MIGRATOR_PASSWORD="$PG_MIGRATION_PASSWORD"
  PYTHONPATH=. python tests/cloud_acceptance.py
)
EVIDENCE_DIR=/tmp/csv-review-desk-evidence PYTHONPATH=. python tests/browser.py
```

Cloud checks include durable invalid-row correction, stable identities/exact integers, stale saves/approval, real observed lock contention, concurrent/repeated approval, edit/approve coordination, a catalogue conflict introduced after validation with total rollback, constraints/provenance, role permissions and certificate/hostname controls. Browser checks use Streamlit's actual upload/editor/approval path and separate sessions to ensure a stale first approval click cannot publish newly changed rows. Set `EVIDENCE_DIR` to your preferred output folder (default `/tmp/csv-review-desk-evidence`); the helper creates it. Screenshots and private programme evidence are not committed.

The browser helper saves `persistence.json` in the evidence folder. To verify actual process persistence, stop Streamlit, start it again from a fresh runtime-only shell as above, then run:

```sh
EVIDENCE_DIR=/tmp/csv-review-desk-evidence PYTHONPATH=. python tests/persistence.py
```

This compares the same approved revision/row identities/values/time and opens its durable batch URL. It does not claim to restore unsaved widget state or a prior browser session.

## Limits and cleanup

Upload requests are not deduplicated; intentionally uploading a file again creates another batch. Names/SKUs are plain text, no URL fetching. No authentication, tax/payment/currency conversion, catalogue update/delete UI, background jobs or arbitrary spreadsheets. No benchmark/index-speed/HA claim. Refreshing a batch can discard unsaved editor text; a durable draft is the last explicitly saved revision. Native Streamlit browser sessions are not the durable state: batches and rows are in Postgres.

Stop Streamlit before cleanup. If retaining the service but removing the example, restore administrator connection fields explicitly:

```sh
source .deployment/resources.env
export PGHOST PGPORT PGDATABASE PGSSLROOTCERT PGSSLMODE=verify-full
export PGUSER="$PGADMIN"
export PGPASSWORD="$(jq -er '.password' .deployment/postgres-create.json)"
psql -X -v ON_ERROR_STOP=1 -f sql/cleanup.sql
unset PGPASSWORD
```

To end Cloud charges, inspect the dedicated service ID/name then delete it:

```sh
clickhousectl cloud postgres get "$PG_SERVICE_ID" --org-id "$CH_ORG_ID" --json
clickhousectl cloud postgres delete "$PG_SERVICE_ID" --org-id "$CH_ORG_ID"
clickhousectl cloud postgres list --org-id "$CH_ORG_ID" --json
```

Confirm the exact ID is absent. Preserve needed source/evidence and stop your Linux VM when finished; no VM deletion is required.
