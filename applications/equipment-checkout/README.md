# Equipment Checkout Board

Borrow shared equipment, see your current loans, and return items with **Django**, **Django ORM**, **psycopg**, and **htmx** on **ClickHouse Managed Postgres (public beta)**. Native Django authentication identifies borrowers. Staff use Django admin to add or disable inventory and can return any current loan.

Two people can see the same available camera. Only one can check it out: a transaction locks the item, and a Postgres partial unique constraint permits one active loan per item. Returns preserve history and are idempotent. An ordinary member can return only their own loans; staff can return anyone's. Available inventory contains no borrower names.

[ClickHouse Cloud](https://clickhouse.com/cloud) is the managed data platform. [ClickHouse Managed Postgres](https://clickhouse.com/docs/products/managed-postgres) provides the transactional PostgreSQL service used here. This example needs only Postgres.

## Structure

| File | Purpose |
| --- | --- |
| `board/models.py`, `board/migrations/` | Inventory, loan history, database constraints |
| `board/services.py` | Item-first locking, borrower identity, repeatable returns |
| `board/views.py`, `board/templates/` | Authenticated HTML and htmx fragments |
| `board/admin.py` | Staff inventory management; read-only loan history |
| `sql/bootstrap.sql`, `sql/grants.sql` | Separate migration and restricted runtime roles |
| `tests/integration.py`, `tests/browser.py` | Real Cloud service and browser acceptance |

A loan belongs to an item and a Django user. `returned_at IS NULL` marks an active loan. `one_active_loan_per_item` is a partial unique index; `return_after_checkout` rejects invalid timestamps. Foreign keys protect referenced equipment and users. Admin disables equipment instead of deleting it, and does not edit loan history.

## Set up in Linux

Use Python 3.12, Git, OpenSSL, `jq`, `psql`, and a ClickHouse Cloud account with Managed Postgres access. Run application dependencies in a Linux environment. An optional dedicated OrbStack VM keeps installations away from your macOS host:

```sh
orb create --memory 3G --cpus 2 ubuntu:24.04 equipment-checkout-dev
orb -m equipment-checkout-dev
```

Inside Linux, clone onto the VM's native filesystem:

```sh
sudo apt-get update
sudo apt-get install -y python3-venv git curl jq openssl postgresql-client
git clone https://github.com/ClickHouse/examples.git ~/examples
cd ~/examples/applications/equipment-checkout
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
umask 077
mkdir -p .deployment
```

`requirements.txt` pins runtime dependencies; `requirements-dev.txt` pins the complete validation environment. htmx 2.0.11 loads from jsDelivr with an integrity hash. CSS uses optional Google Fonts and falls back to local sans-serif fonts. There's no frontend build step.

### 1. Create a dedicated Cloud service

Run Cloud provisioning where you manage resources. Install [clickhousectl](https://clickhouse.com/docs/interfaces/cli), and authenticate with an Admin API key. The interactive prompt keeps secrets out of shell history.

```sh
curl -fsSL https://clickhouse.com/cli | sh
export PATH="$HOME/.local/bin:$PATH"
clickhousectl --version
clickhousectl cloud auth login --interactive
clickhousectl cloud org list
umask 077
mkdir -p .deployment
```

Set your organization ID, supported AWS region, and supported Postgres size in a private `.deployment/resources.env` file. The validation used `c6gd.large` in `us-east-1` with Postgres 18 and no HA; choose from sizes available to your organization. Review [Managed Postgres pricing](https://clickhouse.com/docs/products/managed-postgres/pricing) before provisioning. Compute, storage, backups, and network usage can incur charges. Stopping the app or VM does not delete the Cloud service.

```dotenv
CH_ORG_ID=YOUR_ORGANIZATION_UUID
DEPLOYMENT_NAME=equipment-checkout-example
CLOUD_REGION=us-east-1
PG_SIZE=c6gd.large
```

Create once and preserve the response, which includes the initial administrator password:

```sh
source .deployment/resources.env
clickhousectl cloud postgres create \
  --org-id "$CH_ORG_ID" --name "$DEPLOYMENT_NAME" \
  --provider aws --region "$CLOUD_REGION" --size "$PG_SIZE" \
  --pg-version 18 --ha-type none --tag project=equipment-checkout --json \
  > .deployment/postgres-create.json
PG_SERVICE_ID="$(jq -er '.id' .deployment/postgres-create.json)"
printf 'PG_SERVICE_ID=%s\n' "$PG_SERVICE_ID" >> .deployment/resources.env
```

Repeat `get` until `state` is `running`. Do not repeat creation while waiting:

```sh
clickhousectl cloud postgres get "$PG_SERVICE_ID" \
  --org-id "$CH_ORG_ID" --json > .deployment/postgres-status.json
jq '{id, state, size, postgresVersion}' .deployment/postgres-status.json
```

If creation was interrupted, reconcile the recorded service name against `clickhousectl cloud postgres list --org-id "$CH_ORG_ID" --json` before creating anything else. Fetch the CA only after the service is running:

```sh
clickhousectl cloud postgres certs get "$PG_SERVICE_ID" \
  --org-id "$CH_ORG_ID" --output .deployment/postgres-ca.pem
```

Use `--output` for a PEM file. Redirecting JSON certificate metadata to `.pem` won't produce a usable CA. If provisioning outside Linux, transfer the private create receipt and CA to the Linux app's `.deployment` directory for setup, without copying Cloud API keys.

### 2. Bootstrap roles and apply migrations

The remaining commands run inside Linux from the app directory. Generate these role passwords **once** and preserve the file on retries:

```sh
umask 077
cat > .deployment/passwords.env <<PASSWORDS
EQUIPMENT_MIGRATOR_PASSWORD=Aa1_$(openssl rand -hex 30)
EQUIPMENT_APP_PASSWORD=Aa1_$(openssl rand -hex 30)
PASSWORDS
source .deployment/passwords.env
export EQUIPMENT_MIGRATOR_PASSWORD EQUIPMENT_APP_PASSWORD
export PGHOST="$(jq -er '.hostname' .deployment/postgres-create.json)"
export PGPORT=5432 PGDATABASE=postgres
export PGUSER="$(jq -er '.username' .deployment/postgres-create.json)"
export PGPASSWORD="$(jq -er '.password' .deployment/postgres-create.json)"
export PGSSLMODE=verify-full
export PGSSLROOTCERT="$PWD/.deployment/postgres-ca.pem"
psql -X -v ON_ERROR_STOP=1 -f sql/bootstrap.sql
```

Bootstrap runs once and intentionally fails if these dedicated roles already exist. It creates the `equipment` schema owned by `equipment_migrator`; the runtime login `equipment_app` has no schema creation privileges. The administrator credentials are used only for bootstrap or explicit cleanup.

Django also requires a secret key during migration. Save one generated with `openssl rand -hex 48` in your private environment and retain it across restarts. Changing it invalidates signed sessions.

```sh
export DJANGO_SECRET_KEY="$(openssl rand -hex 48)"
export PGUSER=equipment_migrator
export PGPASSWORD="$EQUIPMENT_MIGRATOR_PASSWORD"
.venv/bin/python manage.py migrate
psql -X -v ON_ERROR_STOP=1 -f sql/grants.sql
export DEMO_PASSWORD="$(openssl rand -hex 18)"
.venv/bin/python manage.py seed_demo
```

Keep `DEMO_PASSWORD` privately to sign in as `alex`, `sam`, or `staff`. The seed creates four inventory items and sets user passwords only on first creation. All seeded users share this development password. `staff` is a superuser so the example exposes native admin inventory management immediately; replace demo users with individually provisioned accounts before hosted use.

Always use the migration login for `migrate`, and rerun `sql/grants.sql` after migrations create tables or sequences. The app login can operate the dedicated application's tables, including Django authentication and sessions, but cannot write `django_migrations`. It is not a database tenant boundary; HTTP authorization enforces member ownership.

### 3. Configure and start the app

```sh
cp .env.example .deployment/app.env
```

Edit `app.env` to use the direct Cloud hostname, `PGUSER=equipment_app`, its password, the absolute CA path, and your saved `DJANGO_SECRET_KEY`. Keep administrator and migration passwords out of this runtime file. Django always uses `sslmode=verify-full` to verify the certificate chain and hostname. `PGSSLMODE` cannot weaken this application default.

```sh
set -a
source .deployment/app.env
set +a
.venv/bin/python manage.py check
.venv/bin/python manage.py runserver 127.0.0.1:8000
```

Open `http://127.0.0.1:8000` from the development environment. For OrbStack, a VM-local browser test can verify the UI without a public listener. Sign in as `alex`, borrow the camera, see it under your current loans, then return it. Sign in as `sam` to verify the active loan is unavailable. As `staff`, use **Manage inventory** to add equipment or disable an item, and return any active loan.

Each write is a POST containing Django's CSRF token. htmx replaces the board fragment after borrowing or returning; ordinary forms work with JavaScript disabled. While the item remains enabled, a repeated borrow by the same owner returns the existing active loan. Disabling an item makes all borrow requests return `409`, including repeats. A return retry leaves the original return timestamp unchanged. A different member's return gets `404`. A conflicting checkout or disabled item gets `409`. Unknown or malformed IDs get `404`; GET writes get `405`. Database failures return a friendly `503` without attempting another database query.

## Validate against a dedicated service

With the server running and runtime environment loaded, open a second Linux shell:

```sh
.venv/bin/python -m pip install -r requirements-dev.txt
PYTHONPATH=. .venv/bin/python tests/integration.py
.venv/bin/playwright install --with-deps chromium
export DEMO_PASSWORD=YOUR_PRIVATE_SEED_PASSWORD
.venv/bin/python tests/browser.py
```

The 13 integration tests create unique fixtures and remove them afterward. They exercise simultaneous checkout requests, disabling inventory during checkout, direct constraint rejection, timestamp validation, return retry behavior, member/staff ownership, CSRF rejection, native admin access and required fields, invalid IDs, disabled equipment, runtime DDL denial, migration-table denial, and verified TLS. Negative TLS checks use both an unrelated CA bundle and a wrong hostname with the correct host address. Browser validation checks login, actual htmx borrow/return swaps, desktop/mobile screenshots, and layout overflow. Tests require a migrated database; they never substitute SQLite or a local Postgres server.

To verify the application migration lifecycle before seeding, use the migration login to run `manage.py migrate board zero`, then `manage.py migrate` and `sql/grants.sql`. This deletes board data: use only an empty dedicated service. The separate process restart check uses the seeded microphone and member `alex`:

```sh
PYTHONPATH=. .venv/bin/python tests/persistence.py before
# Stop the running development server with Ctrl-C, then start it again.
PYTHONPATH=. .venv/bin/python tests/persistence.py after
```

The second command verifies the same session and loan timestamp survived, then returns the microphone. Run it with the private `DEMO_PASSWORD` set. It stores temporary session cookies in the ignored `.deployment` directory. The CI workflow runs Django configuration and Python compilation checks without Cloud credentials; real service checks remain manual.

## Operation and cleanup

The list reflects a snapshot; the borrowing transaction makes the final availability decision. All inventory updates and returns take the item lock before the loan lock. The unique constraint protects active-loan exclusivity independently. Historical loans are retained. The example has no due dates, reservations, email, signup flow, or audit of staff inventory changes.

The development server is bound to localhost. For hosted use, serve static files and run Gunicorn behind HTTPS, set `DJANGO_DEBUG=0`, exact `DJANGO_ALLOWED_HOSTS`, and `DJANGO_COOKIE_SECURE=1`, retain CSRF middleware, and provide login rate limiting at the application gateway. Do not expose the development listener publicly. External htmx and fonts require network access; self-host them if your deployment requires it.

Stop the application. To remove only this example's objects from a service you will retain, review the destructive `sql/cleanup.sql`, reconnect as the administrator, and run it explicitly:

```sh
export PGUSER="$(jq -er '.username' .deployment/postgres-create.json)"
export PGPASSWORD="$(jq -er '.password' .deployment/postgres-create.json)"
psql -X -v ON_ERROR_STOP=1 -f sql/cleanup.sql
```

To delete a service dedicated exclusively to this example and stop its ongoing charges, use the saved exact ID:

```sh
source .deployment/resources.env
clickhousectl cloud postgres get "$PG_SERVICE_ID" --org-id "$CH_ORG_ID" --json
clickhousectl cloud postgres delete "$PG_SERVICE_ID" --org-id "$CH_ORG_ID"
clickhousectl cloud postgres list --org-id "$CH_ORG_ID" --json
```

Confirm the recorded ID is absent. If the administrator password was lost, `clickhousectl cloud postgres reset-password "$PG_SERVICE_ID" --org-id "$CH_ORG_ID" --generate --json` returns a replacement; save it privately. A reset does not change the app or migration passwords. Remove private credential files when no longer needed. Do not run cleanup against a shared service.
