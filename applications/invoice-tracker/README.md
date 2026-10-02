# Invoice tracker

Draft invoices with line items, issue a fixed snapshot, and manually record settlement with **PHP, Laravel, Eloquent and Blade** on **ClickHouse Managed Postgres (public beta)**. Each authenticated user sees only their own invoices. This example records a lifecycle; it does not process payments or integrate tax/accounting systems.

[ClickHouse Cloud](https://clickhouse.com/cloud) is the managed data platform; [ClickHouse Managed Postgres](https://clickhouse.com/docs/products/managed-postgres/overview) is the transactional Postgres service used here.

## Behavior

| Operation | Result |
| --- | --- |
| Create draft | Server chooses the authenticated owner; header and 1–100 lines commit together |
| Save draft | Locks the invoice, replaces all lines atomically, permits draft state only |
| Issue | Locks the same invoice, assigns one unique public number, stores the exact total and JSON snapshot |
| Repeat issue | Returns the existing record; no second number or snapshot |
| Edit after issue | `409`; database triggers also protect issued headers/snapshots and lines |
| Mark settled | Issued only; repeated requests preserve the original settlement time and snapshot |
| Other user's invoice | `404` for reads and mutations |
| Invalid input / missing CSRF | JSON `422` / `419`; browser validation redirects back with errors |

Amounts are **USD integer cents**, parsed from decimal strings without floating-point arithmetic. Quantities are whole numbers from 1 to 1,000; unit prices are USD 0.00–1,000,000.00; invoices contain 1–100 lines. The maximum total is 10^13 cents, within signed 64-bit PHP and Postgres bigint. Inputs like `0.001`, `1e3`, negatives and ambiguous leading zeros are rejected. No tax, discounts, exchange rates or fractional quantities are supported.

Eloquent transactions acquire the invoice row lock before draft replacement, issue or settlement. A concurrent edit either commits fully before issue and appears in the snapshot, or sees issued state and rejects. Two draft saves have **last-writer behavior**; there is no optimistic version check for a stale editing tab. PostgreSQL triggers lock the parent for direct line mutations, reject changes after issue, and protect issued snapshot fields. The shared runtime database login is trusted: these are integrity protections, not tenant isolation from a writer holding database credentials.

Public numbers use a PostgreSQL sequence and a unique constraint (`INV-000001`, then increasing). Sequences can have gaps after rolled-back operations; there is no gapless accounting-number promise. Repeat issue after successful commit preserves the number, total, timestamp and snapshot. Draft creation itself has no request-id deduplication. Settlement is a manual record, not a verified payment event.

The list shows 20 invoices per page. The detail uses the frozen snapshot once issued. Draft edit has a small local JavaScript line editor; Blade pages and ordinary forms require no frontend build. Native Laravel authentication, session middleware, validation and request-forgery protection handle identity. Sessions live in Postgres; cookies contain an encrypted session identifier, with HttpOnly/SameSite=Lax and a two-hour session lifetime. Login regenerates the session; logout invalidates its database row. The acceptance test verifies a replayed old session cookie cannot authenticate after logout. The sign-in throttle uses a local file cache, so multiple hosts need shared controls.

## Linux setup

Use 64-bit PHP 8.3 or newer supported by Laravel 13, Composer, PDO_pgsql, PostgreSQL client tools, Git, jq and OpenSSL. Validation used Ubuntu 24.04 arm64's updated PHP 8.3.6 package, Laravel 13.34.0, Composer 2.7.1 and libpq 16.15. Keep hosting packages updated. Install everything on Linux:

```sh
orb create --memory 3G --cpus 2 ubuntu:24.04 invoice-tracker-dev
orb -m invoice-tracker-dev
sudo apt-get update
sudo apt-get install -y php8.3-cli php8.3-pgsql php8.3-mbstring php8.3-xml php8.3-curl php8.3-zip composer postgresql-client git curl jq openssl
git clone https://github.com/ClickHouse/examples.git ~/examples
cd ~/examples/applications/invoice-tracker
mkdir -p storage/framework/{sessions,views,cache/data} storage/logs bootstrap/cache
composer install --no-interaction --prefer-dist
umask 077
mkdir -p .deployment
cp .env.example .env
php artisan key:generate
```

While reviewing the draft branch, check out `codex/invoice-tracker` before entering the app directory. `composer.lock` pins the dependency set, including PHPUnit and Pint development tools. No Node.js build, SQLite, Redis, external auth service or additional database is needed. Retain `.env` and its generated `APP_KEY` across restarts; keep secrets out of source control. File-serving/upload routes are explicitly disabled.

### 1. Provision a dedicated Cloud service

Install [clickhousectl](https://clickhouse.com/docs/interfaces/cli) where you manage Cloud resources, then authenticate interactively with an Admin API key:

```sh
curl -fsSL https://clickhouse.com/cli | sh
export PATH="$HOME/.local/bin:$PATH"
clickhousectl --version
clickhousectl cloud auth login --interactive
clickhousectl cloud org list
umask 077
mkdir -p .deployment
```

Create a private `.deployment/resources.env` with your organization and an available region/size:

```dotenv
CH_ORG_ID=YOUR_ORGANIZATION_UUID
DEPLOYMENT_NAME=invoice-tracker-example
CLOUD_REGION=us-east-1
PG_SIZE=c6gd.large
```

Validation used AWS us-east-1, `c6gd.large`, Postgres 18, HA none. Check [Managed Postgres pricing](https://clickhouse.com/docs/products/managed-postgres/pricing) and available sizes before creation. Compute, storage, backups and network usage incur charges. Stopping PHP or the VM does not delete the service.

```sh
source .deployment/resources.env
clickhousectl cloud postgres create \
  --org-id "$CH_ORG_ID" --name "$DEPLOYMENT_NAME" \
  --provider aws --region "$CLOUD_REGION" --size "$PG_SIZE" \
  --pg-version 18 --ha-type none --tag project=invoice-tracker --json \
  > .deployment/postgres-create.json
PG_SERVICE_ID="$(jq -er '.id' .deployment/postgres-create.json)"
printf 'PG_SERVICE_ID=%s\n' "$PG_SERVICE_ID" >> .deployment/resources.env
```

Preserve the create receipt: it contains the initial administrator password. Do not repeat creation while waiting. Repeat `get` until its state is `running`, then download the PEM bundle:

```sh
clickhousectl cloud postgres get "$PG_SERVICE_ID" --org-id "$CH_ORG_ID" --json \
  > .deployment/postgres-status.json
jq '{id,state,size,postgresVersion}' .deployment/postgres-status.json
clickhousectl cloud postgres certs get "$PG_SERVICE_ID" --org-id "$CH_ORG_ID" \
  --output .deployment/postgres-ca.pem
```

Use `--output`, not redirected certificate JSON, for the CA file. If creation is interrupted, reconcile the saved name/ID against `cloud postgres list` before creating another service. When provisioning outside Linux, transfer the private create receipt and CA to the Linux `.deployment` folder; do not copy Cloud API keys.

### 2. Bootstrap roles and native migrations

From the Linux application directory, generate role passwords once and retain the file:

```sh
umask 077
cat > .deployment/passwords.env <<PASSWORDS
INVOICE_MIGRATOR_PASSWORD=Aa1_$(openssl rand -hex 30)
INVOICE_APP_PASSWORD=Aa1_$(openssl rand -hex 30)
PASSWORDS
source .deployment/passwords.env
export INVOICE_MIGRATOR_PASSWORD INVOICE_APP_PASSWORD
export PGHOST="$(jq -er '.hostname' .deployment/postgres-create.json)"
export PGPORT=5432 PGDATABASE=postgres
export PGUSER="$(jq -er '.username' .deployment/postgres-create.json)"
export PGPASSWORD="$(jq -er '.password' .deployment/postgres-create.json)"
export PGSSLMODE=verify-full
export PGSSLROOTCERT="$PWD/.deployment/postgres-ca.pem"
psql -X -v ON_ERROR_STOP=1 -f sql/bootstrap.sql
```

Bootstrap creates `invoice_tracker`, its restricted schema-owner login and runtime login. It intentionally fails if they already exist; start with an empty dedicated service. Native migrations create users, database sessions, invoices, lines, constraints, the public-number sequence and integrity triggers.

Edit `.env` with the direct hostname, database, **runtime** identity `DB_USERNAME=invoice_app`, its password and the absolute CA path `DB_SSLROOTCERT`. Use a certificate path without spaces/semicolons because Laravel appends it to the PDO DSN. Keep the generated `APP_KEY`. `config/database.php` always selects PostgreSQL and forces `sslmode=verify-full`; changing an environment `PGSSLMODE` cannot weaken it. The installed Laravel connector appends `sslrootcert` and `sslmode` to PDO_pgsql's DSN, and real wrong-CA/hostname controls verify both.

Temporarily export the migration identity for schema changes; `.env` stays runtime-only:

```sh
export DB_HOST="$PGHOST" DB_PORT="$PGPORT" DB_DATABASE="$PGDATABASE"
export DB_SSLROOTCERT="$PGSSLROOTCERT"
export DB_USERNAME=invoice_migrator DB_PASSWORD="$INVOICE_MIGRATOR_PASSWORD"
export PGUSER=invoice_migrator PGPASSWORD="$INVOICE_MIGRATOR_PASSWORD"
php artisan migrate --force
psql -X -v ON_ERROR_STOP=1 -f sql/grants.sql
export DEMO_PASSWORD="$(openssl rand -hex 18)"
php artisan db:seed --force
```

Preserve the private demo password. Seed users `alex@example.test` and `sam@example.test` each get a sample draft; passwords are set only on first creation. Provision individual accounts before hosted operation. Runtime can read/insert/update invoices, operate draft lines and native sessions, but cannot create schema objects, alter migration records or delete invoices. Rerun grants after migrations add objects.

For an empty-service migration reversal check, `php artisan migrate:rollback --force`, then migrate and reapply grants before seeding. Rollback destroys domain data; never use it as a routine data-preserving upgrade.

### 3. Run with runtime credentials

Start a **fresh Linux shell** in the app directory, so migration exports are not inherited. Laravel reads the runtime-only `.env` automatically. For meaningful competing development requests, use native Linux PHP workers:

```sh
PHP_CLI_SERVER_WORKERS=4 php -S 127.0.0.1:8000 -t public server.php
```

This development server binds localhost. Sign in as Alex, create/edit a draft, issue it and mark it settled. In a separate browser, Sam cannot open Alex's invoice. Issued details remain fixed; refresh/repeat issue without allocating another number.

## Validation

Offline checks need no Cloud credentials:

```sh
composer validate --strict --no-check-all
composer test
vendor/bin/pint --test
php artisan route:list
php artisan view:cache
```

The validation command keeps schema/lock consistency strict while skipping Composer’s opinion on version-range tightness; this example intentionally pins Laravel. PHPUnit runs nine pure arithmetic/validation cases. CI runs these unit and framework/style checks without a live database. Database/HTTP acceptance uses the running dedicated service; never a shared production database. Install Python/browser tools only in Linux:

```sh
sudo apt-get install -y python3-venv
python3 -m venv .deployment/test-venv
.deployment/test-venv/bin/pip install -r tests/requirements.txt
.deployment/test-venv/bin/playwright install --with-deps chromium
```

In a separate test shell, explicitly load the runtime fields and private demo password, then provide the migration password only to the fixture cleanup process:

```sh
set -a
source .env
set +a
export DEMO_PASSWORD=YOUR_PRIVATE_SEED_PASSWORD
export TEST_MIGRATOR_PASSWORD=YOUR_PRIVATE_MIGRATION_PASSWORD
.deployment/test-venv/bin/python tests/acceptance.py
.deployment/test-venv/bin/python tests/browser.py
```

The 13 real-service cases cover competing/repeated issue, coordinated edit-versus-issue, whole snapshots, cross-user denial, server identity, native CSRF/logout revocation, exact totals/invalid input, transaction rollback, bounded pages, direct immutable-row/NULL-total/unique-number rejection, restricted runtime privileges, actual PDO certificate controls and a real middleware outage response. Fixtures use unique user names; cleanup briefly disables the owned line-history trigger inside a migration-role transaction to remove **only those fixture users/invoices**, then restores it. This privilege belongs to fixture cleanup, never the web server.

Browser checks native sign-in, decimal validation, dynamic line editing, exact totals, issue/retry/settlement, cross-user `404`, CSRF `419`, loaded styling and responsive screenshots. Restart validation is separate:

```sh
.deployment/test-venv/bin/python tests/persistence.py before
# Stop all four workers and their parent, then restart with runtime-only .env.
.deployment/test-venv/bin/python tests/persistence.py after
```

It verifies an existing database session and exact issued number/snapshot survive a real worker restart; the saved private cookie file is removed afterward.

## Operation and cleanup

This bounded example omits signup/reset, tax/accounting integrations, actual payments, email/PDF delivery, multi-currency, credits and invoice deletion. It makes no accounting/compliance claim. For hosting, use maintained PHP packages and a production PHP-FPM/web-server setup, `APP_ENV=production`, HTTPS `APP_URL`, `SESSION_SECURE_COOKIE=true`, and a gateway that enforces HTTPS. Restrict database credentials to the server. Use shared rate controls across hosts and retain storage/cache permissions. Debug output is disabled. Hosted deployment, failover and performance benchmarking were not tested.

Stop the owned server. To remove this app from a service you keep, restore the administrator identity and explicitly execute the destructive cleanup:

```sh
set -a
source .env
set +a
export PGHOST="$DB_HOST" PGPORT="$DB_PORT" PGDATABASE="$DB_DATABASE"
export PGSSLMODE=verify-full PGSSLROOTCERT="$DB_SSLROOTCERT"
export PGUSER="$(jq -er '.username' .deployment/postgres-create.json)"
export PGPASSWORD="$(jq -er '.password' .deployment/postgres-create.json)"
psql -X -v ON_ERROR_STOP=1 -f sql/cleanup.sql
```

For a service dedicated to this example, delete the saved exact ID and verify it absent to stop ongoing charges:

```sh
source .deployment/resources.env
clickhousectl cloud postgres get "$PG_SERVICE_ID" --org-id "$CH_ORG_ID" --json
clickhousectl cloud postgres delete "$PG_SERVICE_ID" --org-id "$CH_ORG_ID"
clickhousectl cloud postgres list --org-id "$CH_ORG_ID" --json
```

Deletion can be asynchronous. If the administrator password is lost, `cloud postgres reset-password "$PG_SERVICE_ID" --org-id "$CH_ORG_ID" --generate --json` returns a replacement; save it privately. This does not change the migration/runtime passwords. Keep/remove private files according to your retention needs; do not delete a shared service.
