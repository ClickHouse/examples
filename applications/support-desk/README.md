# Support desk

Create a ticket, keep its replies together, and assign one staff owner with **Rails**, **Active Record**, **pg**, and **Hotwire/Turbo** on **ClickHouse Managed Postgres (public beta)**. Customers see and reply to their own tickets. Staff see the queue, claim unassigned tickets, reply to tickets they own, and close or reopen them.

Two staff members can press **Claim ticket** together. The ticket row lock makes the second request observe the first assignment, so exactly one succeeds. The same lock coordinates replies and closure: an accepted reply happens before closure; a closed ticket rejects new replies until its assigned owner reopens it.

[ClickHouse Cloud](https://clickhouse.com/cloud) is the managed data platform. [ClickHouse Managed Postgres](https://clickhouse.com/docs/products/managed-postgres/overview) is the transactional Postgres service used here. This app needs only that database service.

## Design and behavior

Three tables hold users, tickets, and replies. Native Rails `has_secure_password` stores bcrypt password digests. A ticket has one customer, one nullable assignee, an open/closed status, and a closing timestamp. Replies have a ticket, an author, a body, and a creation timestamp. Foreign keys protect references; checks reject blank/oversize messages and inconsistent status/timestamps. A single assignee column represents one owner; Active Record `with_lock` prevents competing claims from overwriting it.

| Action | Permission and result |
| --- | --- |
| Create ticket with initial message | Customer only; ticket and reply commit together; `303` |
| View ticket | Its customer or any staff member; other customers get `404` |
| Claim | Staff only; unassigned open ticket, or retry by its existing owner; `303` |
| Claim owned by another staff member, or closed | `409`, preserving existing owner |
| Add reply | Customer of open ticket, or its assigned staff owner; `303` |
| Reply to closed ticket | `409`; no new reply |
| Close/reopen | Assigned staff owner only; `303`; repeats preserve closing time |
| Missing/invalid fields | `400` for missing/malformed parameters; `422` for model validation |

The server derives customer/author identity from its authenticated user. Posted user IDs cannot choose an owner. Staff without ownership cannot reply or change status (`403`); customers cannot claim tickets or change their status (`403`). Each state change is a CSRF-protected POST. Sign out uses DELETE with Rails' CSRF protection.

The queue contains 20 tickets per page with newer/older navigation. The conversation defaults to the newest 50 replies in chronological order, with visible page labels and older/newer navigation. Replies order by `created_at, id`, so equal timestamps have a stable tie breaker. Page inputs must be integers from 1 to 999. Successful Turbo forms redirect with `303`; invalid forms render `422`. The conversation uses a Turbo Frame for replies, claims and status changes. Ordinary server-rendered forms also work without JavaScript.

## Setup in Linux

Use Ruby 3.2 or newer compatible with Rails 8.1, Bundler 2.6.9, PostgreSQL client tools, Git, `jq`, OpenSSL and a Cloud account with Managed Postgres access. Validation used Ubuntu 24.04's Ruby 3.2.3 distribution package, Rails 8.1.4 and pg 1.6.2. Use a maintained Ruby runtime for your hosting environment. Install dependencies only in Linux; an optional dedicated OrbStack VM keeps them away from macOS:

```sh
orb create --memory 3G --cpus 2 ubuntu:24.04 support-desk-dev
orb -m support-desk-dev
sudo apt-get update
sudo apt-get install -y ruby ruby-dev build-essential libpq-dev postgresql-client git curl jq openssl
git clone https://github.com/ClickHouse/examples.git ~/examples
cd ~/examples/applications/support-desk
sudo gem install bundler -v 2.6.9 --no-document
bundle _2.6.9_ config set --local path vendor/bundle
bundle _2.6.9_ install
umask 077
mkdir -p .deployment
```

`Gemfile.lock` pins the tested gem set. Importmap and the Turbo gem supply local JavaScript; Propshaft serves assets. There is no Node.js build, Redis, SQLite, cache database, background-job database, or external authentication service.

### 1. Create a dedicated Cloud service

Provision where you manage Cloud resources. Install [clickhousectl](https://clickhouse.com/docs/interfaces/cli), and authenticate with an Admin API key. Use the interactive prompt to keep credentials out of shell history:

```sh
curl -fsSL https://clickhouse.com/cli | sh
export PATH="$HOME/.local/bin:$PATH"
clickhousectl --version
clickhousectl cloud auth login --interactive
clickhousectl cloud org list
umask 077
mkdir -p .deployment
```

Set a private `.deployment/resources.env` file using your organization and an available region/size:

```dotenv
CH_ORG_ID=YOUR_ORGANIZATION_UUID
DEPLOYMENT_NAME=support-desk-example
CLOUD_REGION=us-east-1
PG_SIZE=c6gd.large
```

Validation used `c6gd.large`, Postgres 18 and no HA. Review [ClickHouse Managed Postgres pricing](https://clickhouse.com/docs/products/managed-postgres/pricing) before creation. Compute, storage, backups and network usage can incur charges. Stopping Rails or the VM does not delete a Cloud service.

Create once. Preserve its response, including the initial administrator password:

```sh
source .deployment/resources.env
clickhousectl cloud postgres create \
  --org-id "$CH_ORG_ID" --name "$DEPLOYMENT_NAME" \
  --provider aws --region "$CLOUD_REGION" --size "$PG_SIZE" \
  --pg-version 18 --ha-type none --tag project=support-desk --json \
  > .deployment/postgres-create.json
PG_SERVICE_ID="$(jq -er '.id' .deployment/postgres-create.json)"
printf 'PG_SERVICE_ID=%s\n' "$PG_SERVICE_ID" >> .deployment/resources.env
```

Repeat `get` until `state` is `running`, without repeating creation:

```sh
clickhousectl cloud postgres get "$PG_SERVICE_ID" \
  --org-id "$CH_ORG_ID" --json > .deployment/postgres-status.json
jq '{id, state, size, postgresVersion}' .deployment/postgres-status.json
clickhousectl cloud postgres certs get "$PG_SERVICE_ID" \
  --org-id "$CH_ORG_ID" --output .deployment/postgres-ca.pem
```

Use `--output` for a PEM certificate file. JSON certificate metadata is not a CA bundle. If creation was interrupted, reconcile the exact name/ID against `cloud postgres list` before creating another service. If provisioning outside Linux, transfer the private create receipt and CA into the Linux app's `.deployment` directory for bootstrap; don't copy Cloud API keys.

### 2. Bootstrap roles, migrate, and seed

The remaining commands run in Linux from the application directory. Generate role passwords once and retain the file on retries:

```sh
umask 077
cat > .deployment/passwords.env <<PASSWORDS
SUPPORT_MIGRATOR_PASSWORD=Aa1_$(openssl rand -hex 30)
SUPPORT_APP_PASSWORD=Aa1_$(openssl rand -hex 30)
PASSWORDS
source .deployment/passwords.env
export SUPPORT_MIGRATOR_PASSWORD SUPPORT_APP_PASSWORD
export PGHOST="$(jq -er '.hostname' .deployment/postgres-create.json)"
export PGPORT=5432 PGDATABASE=postgres
export PGUSER="$(jq -er '.username' .deployment/postgres-create.json)"
export PGPASSWORD="$(jq -er '.password' .deployment/postgres-create.json)"
export PGSSLMODE=verify-full
export PGSSLROOTCERT="$PWD/.deployment/postgres-ca.pem"
psql -X -v ON_ERROR_STOP=1 -f sql/bootstrap.sql
```

Bootstrap creates a dedicated `support_desk` schema, a migration login that owns it, and a runtime login without DDL privileges. It intentionally fails if these objects already exist. Use an empty dedicated service for initial setup.

Generate a `SECRET_KEY_BASE` with `openssl rand -hex 64` and save it privately. Retain it across restarts so encrypted cookies stay readable. Then apply native migrations and permissions with the migration login:

```sh
export SECRET_KEY_BASE="$(openssl rand -hex 64)"
export PGUSER=support_desk_migrator
export PGPASSWORD="$SUPPORT_MIGRATOR_PASSWORD"
bundle exec rails db:migrate
psql -X -v ON_ERROR_STOP=1 -f sql/grants.sql
export DEMO_PASSWORD="$(openssl rand -hex 18)"
bundle exec rails db:seed
bundle exec rails zeitwerk:check
```

Preserve `DEMO_PASSWORD` privately. The seed creates customers `alex@example.test`, `sam@example.test`, and staff `morgan@example.test`, `jordan@example.test`, plus one Alex ticket. Passwords are set only on first account creation. Use individually provisioned accounts before hosted operation.

Runtime can select/insert/update users and tickets, and select/insert replies. It cannot edit/delete reply history, change schema, or write migration bookkeeping. Rerun `sql/grants.sql` when migrations create objects. Use the migration login for all schema changes and seed work. Migrations are authoritative; automatic schema dumps are disabled because a dumped schema would attempt schema creation that belongs to privileged bootstrap. Do not use `db:prepare`, `db:setup` or `db:schema:load` for this example. The shared runtime role is not a separate tenant boundary; Rails enforces ownership.

### 3. Run the app

```sh
cp .env.example .deployment/app.env
```

Edit the runtime file with the direct service hostname, `PGUSER=support_desk_app`, its password, absolute CA path, and saved `SECRET_KEY_BASE`. Keep administrator/migration passwords out of it. `config/database.yml` forces `sslmode=verify-full`, verifying both certificate chain and hostname through pg/libpq; an environment `PGSSLMODE` cannot weaken it.

```sh
set -a
source .deployment/app.env
set +a
bundle exec puma -C config/puma.rb
```

The listener binds to `127.0.0.1:3000`. Open it from the development environment. As Alex, create a ticket and send a message. In a separate browser session, sign in as Morgan, claim it, reply, close it, then reopen it. Alex can reply again after reopening. Jordan can see it but cannot overwrite Morgan's claim or reply as its owner. Sam cannot read Alex's ticket.

Rails uses an encrypted client-side CookieStore with a 12-hour expiry. It stores user identity in the cookie, while every request loads the user and derives database ownership server-side. Identity is not stored in a database session table. `reset_session` renews/clears the current browser session during sign-in/sign-out, but does **not** revoke a previously stolen/replayed cookie on the server. Add database-backed sessions or a revocation mechanism if that is required. The single-process sign-in limiter uses a bounded in-memory store; add shared gateway controls for multiple processes or hosts.

## Real Cloud validation

Run the server in one Linux shell and tests in another with the runtime environment loaded. The Ruby acceptance suite uses Active Record plus real authenticated HTTP requests, not Rails' test database creation task. Provide the migration password separately for removing only its uniquely named fixtures:

```sh
export TEST_MIGRATOR_PASSWORD=YOUR_PRIVATE_MIGRATION_PASSWORD
bundle exec rails runner test/acceptance.rb
```

The 12 tests exercise simultaneous claims, repeated/competing claims, ticket+initial-reply rollback, author identity, cross-customer/staff permissions, CSRF, validation, reply ordering, bounded pages, closure racing a reply, closed-state rejection, schema/reply-history restrictions and certificate-specific TLS negative controls. Cleanup uses the migration role and removes only these fixture users/tickets/replies. Don't run it against a shared application database.

Browser tooling installs only in Linux:

```sh
sudo apt-get install -y python3-venv
python3 -m venv .deployment/browser-venv
.deployment/browser-venv/bin/pip install -r test/requirements.txt
.deployment/browser-venv/bin/playwright install --with-deps chromium
export DEMO_PASSWORD=YOUR_PRIVATE_SEED_PASSWORD
.deployment/browser-venv/bin/python test/browser.py
```

The browser checks customer/staff sign-in, ticket creation, actual Turbo frame claims/replies/status changes, `422` validation rendering, desktop/mobile screenshots and mobile overflow. CI runs Rails eager-loading, routes, and Ruby syntax checks without Cloud credentials. Real database tests remain manual.

To verify migration reversal before seeding, use `bundle exec rails db:rollback`, then `bundle exec rails db:migrate` and rerun grants. Rollback deletes all domain data: use only an empty dedicated service. Restart validation is separate:

```sh
.deployment/browser-venv/bin/python test/persistence.py before
# Stop Puma with Ctrl-C, then start it again using the same runtime environment.
.deployment/browser-venv/bin/python test/persistence.py after
```

It creates a customer ticket/reply, stores the session cookie privately, and verifies that identity and the exact conversation survive an actual process restart. It does not claim server-side session revocation.

## Operation and cleanup

This example omits signup/password-reset, inbound email, attachments, notifications, transfer/escalation, ticket deletion and reply editing. Staff ownership checks are an application protocol; a direct writer with the shared runtime credentials can bypass role/business rules. Restrict those credentials to the server. Repeat claims preserve an existing open assignment; closed-ticket claims conflict. Reply submission has no request-id deduplication, so retrying a submitted message can append a duplicate reply.

For hosted operation use a maintained Ruby runtime, `RAILS_ENV=production`, exact `APP_HOSTS`, `COOKIE_SECURE=1`, and HTTPS. Production forces SSL. Precompile static assets with `bundle exec rails assets:precompile` using the required configuration. Default server binding remains localhost; put a reverse proxy in front. The interface uses system sans-serif fallbacks without external font requests. Hosted deployment, failover and performance benchmarking were not tested.

Stop Puma. To remove this app from a service you'll keep, reconnect as the administrator and explicitly run the destructive cleanup script:

```sh
export PGUSER="$(jq -er '.username' .deployment/postgres-create.json)"
export PGPASSWORD="$(jq -er '.password' .deployment/postgres-create.json)"
psql -X -v ON_ERROR_STOP=1 -f sql/cleanup.sql
```

For a service dedicated exclusively to this example, verify the saved ID and delete it to stop ongoing charges:

```sh
source .deployment/resources.env
clickhousectl cloud postgres get "$PG_SERVICE_ID" --org-id "$CH_ORG_ID" --json
clickhousectl cloud postgres delete "$PG_SERVICE_ID" --org-id "$CH_ORG_ID"
clickhousectl cloud postgres list --org-id "$CH_ORG_ID" --json
```

Deletion can be asynchronous; confirm the exact ID is absent. If the administrator password is lost, `cloud postgres reset-password "$PG_SERVICE_ID" --org-id "$CH_ORG_ID" --generate --json` returns a replacement; save it privately. It doesn't change separate migration/runtime passwords. Remove private files when no longer needed, and don't clean up a shared service.
