# Room calendar

An authenticated JSON API using Symfony, Doctrine ORM/DBAL/Migrations and PostgreSQL PDO with ClickHouse Managed Postgres (public beta). Seeded members reserve seeded rooms, reschedule their own reservations, cancel them and read shared availability. PostgreSQL's active-only GiST exclusion constraint prevents overlapping bookings in the same room, including concurrent requests.

Intervals are start-inclusive/end-exclusive: `[09:00,10:00)` and `[10:00,11:00)` are adjacent and allowed. Inputs require ISO8601 seconds with `Z` or an explicit `±HH:mm` offset; responses normalize to UTC. Equal instants expressed with different offsets still collide. No ambiguous local times, fractional seconds, infinite timestamps or recurrence rules are accepted. Instants must be within UTC years 2000–2100, with positive booking duration at most 12 hours.

The two server-configured 256-bit tokens identify seeded members. All signed-in members see active reservation titles/intervals; responses omit internal member IDs. Only the owner can reschedule/cancel a reservation, and forged ownership fields are rejected. Tokens are a small example's trust boundary, without signup, credential rotation UI, invitations, email or calendar-provider integration. A trusted shared database role can bypass the API ownership policy; credentials are not database-enforced tenant isolation.

## Native prerequisites and locked build

Use native Linux PHP 8.3 with PostgreSQL PDO, mbstring, XML and intl; Composer, Python 3, psql and OpenSSL. The verified Ubuntu 24.04 ARM64 package was PHP 8.3.6-0ubuntu0.24.04.11 (distribution security fixes), with Symfony 7.4.20 LTS, Doctrine ORM 3.7.3, DBAL 4.5.0, DoctrineBundle 2.19.1, MigrationsBundle 3.7.1 and PHPUnit 12.5.37. PHP 8.3 cannot run the newer Doctrine bundle lines that require PHP 8.4. `composer.lock` pins the complete resolved graph; use install to reproduce it.

```bash
sudo apt-get update
sudo apt-get install -y php8.3-cli php8.3-pgsql php8.3-mbstring php8.3-xml \
  php8.3-curl php8.3-intl unzip git curl ca-certificates python3 postgresql-client openssl jq
curl -fsSLo composer-setup.php https://getcomposer.org/installer
expected=$(curl -fsS https://composer.github.io/installer.sig)
actual=$(php -r "echo hash_file('sha384', 'composer-setup.php');")
test "$actual" = "$expected"
mkdir -p "$HOME/.local/bin"
php composer-setup.php --install-dir="$HOME/.local/bin" --filename=composer
export PATH="$HOME/.local/bin:$PATH"
git clone https://github.com/ClickHouse/examples.git
cd examples/applications/room-calendar
composer install --no-interaction
composer validate --strict
composer audit
composer lint
composer test
```

Lint and three unit tests / 24 assertions need no database credentials. `bin/preflight.php` also checks real Symfony JSON null handling and Doctrine metadata with placeholder connection fields; it never connects to a database. CI supplies those placeholders and compiles the production container.

## Create the owned Cloud service

Install [clickhousectl](https://github.com/ClickHouse/clickhousectl) and authenticate with your Cloud API key in a private terminal. Cloud services incur charges. This fixture needs no HA; its tested shape is c6gd.large in AWS us-east-1. Verify available shapes for your deployment.

```bash
curl -fsSL https://clickhouse.com/cli | sh
export PATH="$HOME/.local/bin:$PATH"
clickhousectl cloud auth login --interactive
umask 077
mkdir -p .deployment
export CH_ORG_ID=YOUR_ORG_ID
clickhousectl cloud postgres create --org-id "$CH_ORG_ID" \
  --name room-calendar-pg --provider aws --region us-east-1 \
  --size c6gd.large --pg-version 18 --ha-type none --json > .deployment/postgres-create.json
export PG_ID=$(jq -r .id .deployment/postgres-create.json)
clickhousectl cloud postgres get "$PG_ID" --org-id "$CH_ORG_ID" --json \
  > .deployment/postgres-status.json
jq -r .state .deployment/postgres-status.json
```

Repeat get until running within a bounded provisioning window. Preserve the original ID after a timeout instead of creating another service. Create returns the administrator password once; get does not reveal it.

```bash
clickhousectl cloud postgres certs get "$PG_ID" --org-id "$CH_ORG_ID" \
  --output "$PWD/.deployment/ca.pem"
jq -r '"export PGHOST="+(.hostname|@sh), "export PGPORT=5432",
       "export PGDATABASE=postgres", "export PGUSER="+(.username|@sh),
       "export PGPASSWORD="+(.password|@sh)' \
  .deployment/postgres-create.json > .deployment/admin.env
printf 'export PGSSLROOTCERT=%q\n' "$PWD/.deployment/ca.pem" >> .deployment/admin.env
printf 'export PGSSLMODE=verify-full\nexport PGCONNECT_TIMEOUT=5\n' >> .deployment/admin.env
source .deployment/admin.env
psql -X -v ON_ERROR_STOP=1 -c "SELECT version(); SELECT name,default_version FROM pg_available_extensions WHERE name='btree_gist';"
```

The live run on 2 October 2026 used PostgreSQL 18.6 and actually installed btree_gist 1.8. Check availability before continuing; the [extension catalogue](https://clickhouse.com/docs/products/managed-postgres/extensions) is a research reference, not proof of your service's installed version.

## Roles, migrations and seed

Generate private role passwords and distinct member tokens:

```bash
python3 - <<'PY'
import pathlib,secrets,shlex
values={name:'Aa1!'+secrets.token_hex(30) for name in
        ['CALENDAR_MIGRATOR_PASSWORD','CALENDAR_APP_PASSWORD']}
values.update({name:secrets.token_hex(32) for name in
               ['MEMBER_001_TOKEN','MEMBER_002_TOKEN','APP_SECRET']})
pathlib.Path('.deployment/passwords.env').write_text(''.join(
    'export '+name+'='+shlex.quote(value)+'\n' for name,value in values.items()))
PY
source .deployment/passwords.env
psql -X -v ON_ERROR_STOP=1 -v migrator_password="$CALENDAR_MIGRATOR_PASSWORD" \
  -v app_password="$CALENDAR_APP_PASSWORD" -f sql/bootstrap.sql
PGUSER=calendar_migrator PGPASSWORD="$CALENDAR_MIGRATOR_PASSWORD" \
  PGOPTIONS='-c role=calendar_owner' php bin/console doctrine:migrations:migrate --no-interaction
PGUSER=calendar_migrator PGPASSWORD="$CALENDAR_MIGRATOR_PASSWORD" \
  PGOPTIONS='-c role=calendar_owner' psql -X -f sql/seed.sql
```

`bootstrap.sql` is administrator-only and runs once on an empty role/schema fixture. It installs btree_gist in a separate extension schema. A NOLOGIN owner is assumed by the NOINHERIT migrator through the explicit startup role option. The migrator's configured search path places the migration-version table in `calendar`; runtime cannot create it. Run migrations through one setup process. Repeating migrate is a no-op and repeating seed preserves reservations. To reverse the application migration, use the same migrator fields/startup role with `doctrine:migrations:execute 'DoctrineMigrations\Version202610020001' --down --no-interaction`; then migrate again.

The reviewed migration deliberately includes this database guarantee:

```sql
CONSTRAINT active_room_no_overlap EXCLUDE USING gist (
  room_id WITH =,
  tstzrange(start_at,end_at,'[)') WITH &&
) WHERE (status='active')
```

Finite endpoint/duration checks and foreign keys also live in the migration. Don't replace this with UNIQUE, an availability precheck, automatic schema synchronization or an unreviewed generated migration. The runtime can select rooms/reservations, insert reservations and update only interval/status/revision columns. It cannot delete reservations, change room/member/title identity columns, install extensions or create schema objects.

## Start and use the API

Create a runtime-only file, with no migration/administrator credentials:

```bash
python3 - <<'PY'
import os,pathlib,shlex
values={name:os.environ[name] for name in
        ['PGHOST','PGPORT','PGDATABASE','PGSSLROOTCERT','APP_SECRET','MEMBER_001_TOKEN','MEMBER_002_TOKEN']}
values.update(PGUSER='calendar_app',PGPASSWORD=os.environ['CALENDAR_APP_PASSWORD'])
pathlib.Path('.deployment/app.env').write_text(''.join(
    'export '+name+'='+shlex.quote(value)+'\n' for name,value in values.items()))
PY
```

Open a new terminal that has not sourced setup credentials (a nested shell inherits exported secrets):

```bash
source .deployment/app.env
php bin/console cache:clear --no-warmup
PHP_CLI_SERVER_WORKERS=4 php -d post_max_size=8K -S 127.0.0.1:8080 -t public public/index.php
```

The PHP CLI server is a local demonstration runner with four forked workers plus its parent, allowing genuine concurrent requests. Use an appropriate managed PHP deployment for a retained application. Runtime PDO uses libpq verify-full, separate connection fields/password, downloaded CA and connect timeout 5 s. Role statement/lock limits are 5 s / 2 s; these layers aren't one overall response deadline.

In another terminal that has loaded only `.deployment/app.env`:

```bash
curl -sS -H "Authorization: Bearer $MEMBER_001_TOKEN" http://127.0.0.1:8080/rooms
curl -sS -H "Authorization: Bearer $MEMBER_001_TOKEN" -H 'Content-Type: application/json' \
  -d '{"roomId":"00000000-0000-4000-8000-000000000101","title":"Planning","startAt":"2026-10-05T09:00:00+01:00","endAt":"2026-10-05T10:00:00+01:00"}' \
  http://127.0.0.1:8080/reservations
# Replace RESERVATION_ID with the returned id.
curl -sS -H "Authorization: Bearer $MEMBER_001_TOKEN" -H 'Content-Type: application/json' \
  -d '{"expectedRevision":1,"startAt":"2026-10-05T10:00:00+01:00","endAt":"2026-10-05T11:00:00+01:00"}' \
  http://127.0.0.1:8080/reservations/RESERVATION_ID/reschedule
curl -sS -H "Authorization: Bearer $MEMBER_001_TOKEN" -H 'Content-Type: application/json' \
  -d '{"expectedRevision":2}' http://127.0.0.1:8080/reservations/RESERVATION_ID/cancel
curl -sS -G -H "Authorization: Bearer $MEMBER_001_TOKEN" \
  --data-urlencode roomId=00000000-0000-4000-8000-000000000101 \
  --data-urlencode from=2026-10-05T00:00:00Z --data-urlencode to=2026-10-06T00:00:00Z \
  http://127.0.0.1:8080/reservations
```

Create returns 201, overlap/stale/cancelled transitions return 409, and foreign changes return 404 without locking the foreign row. Reschedule/cancel lock an owner-filtered reservation and compare the revision the member saw. A rejected reschedule preserves its prior interval/revision. Cancel retains the row and frees its occupied range. A repeated cancellation matches either the resulting revision or its immediately preceding revision and returns the existing cancelled state; older revisions conflict. Rescheduling a cancelled reservation is rejected.

Ordinary creation isn't idempotent. After a lost acknowledgement, inspect the bounded availability window before deciding whether to create again. A cancel/create race can return create 201 if cancellation has freed the range, or 409 if it hasn't; a later create can succeed. No active overlaps are allowed in either outcome. Failed ORM transactions close the EntityManager; the Workflow resets it and discards detached state before another unit of work. SQLState 23P01 becomes a safe 409, without driver SQL/credentials in the response.

Request bodies are at most 4 KiB, titles 120 characters without controls, and revisions JSON integers 1–1,000,000,000. Unknown fields and malformed UTF-8 are rejected. Lists accept an explicit-offset positive window at most 31 days and return at most 100 active DTOs ordered by `(startAt,id)`, with `hasMore` when truncated. Narrow the window if truncated; this small API has no cursor or snapshot pagination. Cancelled history remains in Postgres and isn't included in availability responses.

## Verify and clean up

In a separate test terminal, source `.deployment/admin.env` and `.deployment/passwords.env`; keep the running server on its original runtime file. The checks mutate only synthetic fixture reservations, so use an empty owned test fixture:

```bash
python3 checks/cloud.py
# The manager lifecycle fixture uses 20 November 2026; run once on clean dates.
source .deployment/app.env
php checks/manager-lifecycle.php
php bin/security.php
```

`bin/security.php` uses the actual configured Doctrine/PDO path. With an unrelated valid CA PEM set `PGSSLROOTCERT` and `EXPECTED_TLS_FAILURE=ca`; with the same endpoint's resolved IP set `PGHOST` and `EXPECTED_TLS_FAILURE=hostname`. Keep verify-full enabled. The controls check specific certificate/name errors and SQLState 08006, with positive control TLS 1.3.

For reproducible restart evidence, start the server using `checks/launch.py` with `EVIDENCE_DIR` set to a private evidence directory instead of the foreground start command, then run `checks/restart.py`. It kills the original process group, asserts it is gone, starts a runtime-only group and compares authenticated availability. Reservation state survives restart. These helpers load an explicit runtime variable whitelist and exclude PGOPTIONS/migration/admin secrets.

Verified live: actual simultaneous overlap 201/409; adjacency/different rooms/different offsets; reschedule rollback; stale/foreign changes; foreign 404 while an owner row lock remains held; cancel/create race; independent direct database exclusion/finite checks; native body/input bounds; real EntityManager recovery on the same PHP workflow; actual server-group restart; TLS/role controls; 101-row listing fixture returning 100 plus hasMore. No performance claim follows from the index or small fixture.

Stop the runtime first. Any retained-schema cleanup must explicitly source `.deployment/admin.env`; the runtime file leaves PGUSER/PGPASSWORD on the restricted role. Delete only your owned service when finished:

```bash
clickhousectl cloud postgres delete "$PG_ID" --org-id "$CH_ORG_ID"
clickhousectl cloud postgres list --org-id "$CH_ORG_ID" --json
```

Confirm the exact ID is absent. Preserve public source/evidence and keep private credentials out of Git.

Primary references: [PostgreSQL range constraints](https://www.postgresql.org/docs/current/rangetypes.html#RANGETYPES-CONSTRAINT), [Doctrine transaction lifecycle](https://www.doctrine-project.org/projects/doctrine-orm/en/3.7/reference/transactions-and-concurrency.html), [Symfony 7.4 release](https://symfony.com/releases/7.4), [PDO connection/TLS parameters](https://www.doctrine-project.org/projects/doctrine-dbal/en/4.5/reference/configuration.html), [Managed Postgres overview](https://clickhouse.com/docs/products/managed-postgres/overview).
