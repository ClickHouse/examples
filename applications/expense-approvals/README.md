# Expense approvals with Spring Boot and Postgres

A small Java approval API backed by ClickHouse Managed Postgres (public beta) in ClickHouse Cloud. Employees create and edit drafts, submit them, and inspect their status. Managers decide submitted requests. A version in every write prevents stale updates from silently replacing a competing edit or decision. This example enters expenses manually; it makes no payments.

Java 21, Spring Boot 4.1.1, Spring Data JPA and Hibernate 7.4.5.Final, Flyway 12.4.0 and pgJDBC 42.7.13. The Boot BOM manages compatible dependency versions; Maven Wrapper pins Maven 3.9.11. No local Postgres or H2 is used for acceptance.

## API and trust boundary

Demo bearer tokens map to immutable identities and EMPLOYEE or MANAGER roles in `APP_TOKENS`. Generate a different random token for each identity with `openssl rand -hex 24`. Keep tokens secret and preserve identity/role when rotating them. The server derives ownership from the token; unknown JSON properties, including `ownerId`, are rejected. SHA-256 token digests are compared with constant-time comparisons. This is a demo for trusted API clients, without registration, token issuance or revocation storage. Use HTTPS at a trusted proxy before remote deployment; the default bind address is loopback. There is no browser cookie authentication or CORS configuration.

Employees see only their own requests. Managers see their own drafts plus all submitted and decided requests. Managers may also create, edit and submit their own requests, but cannot approve **or reject** their own requests. Only owners edit/submit drafts. Decisions are terminal. Lists optionally filter by status, return the newest 100 visible rows, and sort by `createdAt DESC, id DESC`. There is no pagination or total count.

| Method | Route | Body / behavior |
|---|---|---|
| GET | `/health` | Anonymous process health, not a database readiness check |
| POST | `/expenses` | `description`, decimal `amount`, `currency` |
| GET | `/expenses?status=SUBMITTED` | Visible requests; status is optional |
| GET | `/expenses/{id}` | Visible request with current version |
| PUT | `/expenses/{id}` | Full draft fields and `version` |
| POST | `/expenses/{id}/submit` | Owner, draft, `version` |
| POST | `/expenses/{id}/approve` | Manager, another owner's submitted request, `version`, optional `note` |
| POST | `/expenses/{id}/reject` | Same, with a nonblank `note` |

Amounts use Java `BigDecimal` and PostgreSQL `numeric(8,2)`, from GBP 0.01 to 100000.00, with at most two decimal places. Responses encode the amount as a fixed decimal string to avoid floating-point conversion by clients. Descriptions must be nonblank and at most 300 input characters; stored descriptions are trimmed; notes are at most 500. Errors return JSON `error`: 400 invalid input, 401 missing/invalid token, 403 forbidden operation, 404 inaccessible/missing request, 409 stale version or invalid state.

## Build

Install JDK 21, Python 3 and a PostgreSQL client. Run inside this directory:

```sh
./mvnw -B verify
```

The default build runs four database-independent domain tests and packages the application. It does not connect to Cloud. The `cloud` Maven profile runs the separate Cloud tests.

## Create the dedicated Cloud service

Install [clickhousectl](https://github.com/ClickHouse/clickhousectl) and authenticate using your Cloud API credentials. The following commands match clickhousectl 0.5.0. Pick a supported size and region for your organization; this fixture used `c6gd.large` in `us-east-1`, Postgres 18, without HA. Creating a service incurs Cloud charges; delete it after testing. Check current options and pricing in the [Managed Postgres quickstart](https://clickhouse.com/docs/products/managed-postgres/quickstart).

```sh
clickhousectl cloud postgres create --name expense-approvals-demo \
  --provider aws --region us-east-1 --size c6gd.large \
  --pg-version 18 --ha-type none --json > service-private.json
chmod 600 service-private.json
# Set SERVICE_ID to the returned id. Poll until state is running:
clickhousectl cloud postgres get "$SERVICE_ID" --json
clickhousectl cloud postgres certs get "$SERVICE_ID" --output cloud-ca.pem
```

Keep the receipt outside the repository: it contains the initial administrator password, which later `get` calls do not return. Keep the endpoint, passwords and CA file private. Copy `.env.example` to a private environment file, use the returned hostname and an absolute CA path, and set your generated tokens. Never paste a connection string into source or shell history. Both pgJDBC and `psql` verify the CA and hostname: `PGSSLMODE=verify-full`, and the application's Hikari properties explicitly set `sslmode=verify-full` and `sslrootcert`.

## Bootstrap, migrate, grant and seed

Use a fresh dedicated service. Set `PGHOST`, `PGPORT=5432`, `PGDATABASE=postgres`, `PGSSLMODE=verify-full`, `PGSSLROOTCERT` and administrator `PGUSER` / `PGPASSWORD` in your shell. Generate two different random database passwords and export `MIGRATION_PASSWORD` and `APP_PASSWORD` privately. These commands do not print their values, but take care on shared machines because psql arguments may be visible to other local users.

```sh
psql -X -v ON_ERROR_STOP=1 \
  -v migration_password="$MIGRATION_PASSWORD" \
  -v app_password="$APP_PASSWORD" -f sql/bootstrap.sql
```

The administrator creates `expense_migration`, `expense_app` and schema `expenses`, owned by the migration role. PUBLIC loses CREATE in schema `public` on this dedicated service. The runtime role gets schema USAGE. Flyway does not create a schema or require database CREATE; it creates its history table in the existing owned schema.

Run the explicit migration entry point with only the migration credential:

```sh
PGUSER=expense_migration PGPASSWORD="$MIGRATION_PASSWORD" \
java -Dloader.main=com.example.expenses.SchemaMigrate \
  -jar target/expense-approvals-1.0.0.jar
```

With the administrator credential still set in the shell, grant only CRUD on the expense table:

```sh
psql -X -v ON_ERROR_STOP=1 -f sql/grants.sql
```

Then use the runtime credential to insert two sample requests:

```sh
PGUSER=expense_app PGPASSWORD="$APP_PASSWORD" \
psql -X -v ON_ERROR_STOP=1 -f sql/seed.sql
```

Migration and seed commands can be repeated: Flyway validates/applies only missing versioned migrations; the seed uses fixed UUIDs with `ON CONFLICT DO NOTHING`. Runtime cannot read Flyway history or create tables. Hibernate uses `ddl-auto=validate`, SQL initialization is disabled, and API startup never invokes the migration entry point. Keep administrator and migration variables out of the runtime environment.

## Start and try the workflow

Start a fresh shell, load only your runtime environment and tokens, then:

```sh
java -jar target/expense-approvals-1.0.0.jar
```

The server listens on `127.0.0.1:8080`. An explicit `APP_BIND_ADDRESS` override is available for a trusted deployment. Set `EMPLOYEE_TOKEN` and `MANAGER_TOKEN` privately to tokens from your mapping.

```sh
curl -sS http://127.0.0.1:8080/expenses \
  -H "Authorization: Bearer $EMPLOYEE_TOKEN" -H 'Content-Type: application/json' \
  -d '{"description":"Notebook","amount":"12.34","currency":"GBP"}'
# Set EXPENSE_ID to the response id; its initial version is 0.
curl -sS http://127.0.0.1:8080/expenses/$EXPENSE_ID/submit \
  -H "Authorization: Bearer $EMPLOYEE_TOKEN" -H 'Content-Type: application/json' \
  -d '{"version":0}'
curl -sS http://127.0.0.1:8080/expenses/$EXPENSE_ID/approve \
  -H "Authorization: Bearer $MANAGER_TOKEN" -H 'Content-Type: application/json' \
  -d '{"version":1}'
```

The approval returns version 2. Repeating an action with an earlier version returns 409; refetch the current request before deciding what to do. There is no automatic retry of a business decision. Each write checks actor, expected version and state inside a Spring transaction. `@Version` also protects requests that both loaded the same version. Flushing inside the service raises version conflicts before forming the response; the exception handler also covers transaction exceptions propagated through the controller.

## Cloud acceptance

Use the dedicated fixture, runtime environment and the four identities in `.env.example`. The suite creates/deletes only its random fixture rows. Keep production data away from it. Run:

```sh
./mvnw -B -Pcloud verify
python3 scripts/acceptance.py
```

Five Cloud JUnit tests cover a barrier-coordinated native JPA race, rollback after a real flush, restricted runtime privileges/TLS, wrong-CA rejection and malformed SQL decision rows. The HTTP script starts the packaged jar on loopback port 8081, exercises validation/unknown-owner rejection, cross-user reads, role/self-decision checks, status filtering, stale writes, three edit/submit races and three manager-decision races. Each race requires one 200 and one 409. It restarts the production process and compares the persisted request, then removes its generated rows with the runtime credential. Application output defaults to `/tmp/expenses-app.log`; use `APP_LOG` for a private log path. The wrong-CA control uses the system trust bundle, which must not contain this service's private CA.

The owner/created and status/created indexes support common filters. This example has no pagination, audit-event history, attachments, reimbursements or payment integration.

## Cleanup

Stop the application. On your dedicated service, switch to the administrator credential and optionally remove the example schema and roles:

```sh
psql -X -v ON_ERROR_STOP=1 -f sql/cleanup.sql
clickhousectl cloud postgres delete "$SERVICE_ID"
clickhousectl cloud postgres list --json
```

Deletion is asynchronous: verify the recorded ID disappears from the list. Delete only the dedicated service you created, and remove private local credential receipts when no longer needed.

## Sources

[Spring Boot SQL support](https://docs.spring.io/spring-boot/reference/data/sql.html), [database initialization](https://docs.spring.io/spring-boot/how-to/data-initialization.html), [Spring transactions](https://docs.spring.io/spring-framework/reference/data-access/transaction/declarative.html), [Spring Data JPA locking](https://docs.spring.io/spring-data/jpa/reference/jpa/locking.html), [pgJDBC TLS](https://jdbc.postgresql.org/documentation/ssl/).
