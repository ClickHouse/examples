# Document revisions with Quarkus and Panache

A JSON API for account-owned documents on ClickHouse Managed Postgres. Editing appends an immutable text snapshot and advances a draft pointer. Publishing independently selects an existing revision. New drafts leave published content unchanged.

Quarkus REST handles HTTP, native Quarkus security maps two seeded accounts to bearer tokens, Hibernate ORM Panache supplies scoped queries and row locks, and Flyway owns schema changes. The application runs on the JVM. It has no frontend, arbitrary HTML, external storage or real deployment integration.

The verified stack is Java 21, Maven 3.10.0, Quarkus 3.40.1 (3.40 LTS), Hibernate ORM 7.4.9.Final, Flyway 12.0.0 and pgJDBC 42.7.13. The Quarkus BOM pins the library graph; explicit build plugin versions live in `pom.xml`. Live acceptance used PostgreSQL 18.6 in ClickHouse Cloud.

## Native build

Use a Linux machine with JDK 21 and Maven 3.10.0. On Ubuntu, install the utilities first:

```bash
sudo apt-get update
sudo apt-get install -y openjdk-21-jdk-headless curl ca-certificates python3 postgresql-client jq openssl
```

Install [Apache Maven 3.10.0](https://maven.apache.org/download.cgi) from its official release archive, checking the published SHA-512. The tested release checksum was:

```text
908b1501bfb420bf7c8affb855534a9c407fd6099367bfb9f2f2dcb8e9799102bffb84518cde74c679bd76870247c6528683abdd620581bffa90f95d92d175aa
```

From this application directory:

```bash
mvn -B -ntp clean package
```

This runs input and JDBC endpoint boundary tests and produces `target/quarkus-app/quarkus-run.jar`. It requires no database or Cloud credentials. Dev Services, ORM schema generation, SQL auto-loading and Flyway startup migrations are disabled. There is no container-backed substitute for Cloud acceptance.

## Create an isolated Cloud database

Install [clickhousectl](https://clickhouse.com/blog/getting-started-clickhousectl), authenticate with your own Cloud API key, and select your organization. These commands use clickhousectl 0.5.0. The example creates a billable AWS service without HA; choose a supported size and region for your organization.

```bash
umask 077
mkdir -p "$HOME/document-private"
clickhousectl cloud postgres create --org-id YOUR_ORG_ID \
  --name document-revisions-example --provider aws --region us-east-1 \
  --size c6gd.large --pg-version 18 --ha-type none \
  > "$HOME/document-private/create.json"
```

The create response contains credentials once. Save its ID as `PG_ID`. Check until its state is `running`, then retrieve the official CA bundle:

```bash
export PG_ID=YOUR_CREATED_POSTGRES_ID
clickhousectl cloud postgres get "$PG_ID" --org-id YOUR_ORG_ID
clickhousectl cloud postgres certs get "$PG_ID" --org-id YOUR_ORG_ID \
  --output "$HOME/document-private/ca.pem"
```

Create a private setup environment using the hostname, username and password from the receipt. The connection port is 5432 and the database is `postgres` for this fixture. Generate independent setup/runtime passwords and two 256-bit account tokens:

```bash
export PGHOST=YOUR_CLOUD_POSTGRES_HOST PGPORT=5432 PGDATABASE=postgres
export PGUSER=YOUR_CLOUD_ADMIN_USER PGPASSWORD=YOUR_CLOUD_ADMIN_PASSWORD
export PGSSLROOTCERT="$HOME/document-private/ca.pem" PGSSLMODE=verify-full
export PGCONNECT_TIMEOUT=5
export MIGRATOR_PASSWORD="Aa1$(openssl rand -hex 24)"
export APP_PASSWORD="Aa1$(openssl rand -hex 24)"
export ACCOUNT_001_TOKEN="$(openssl rand -hex 32)"
export ACCOUNT_002_TOKEN="$(openssl rand -hex 32)"
export JDBC_URL="$(python3 checks/jdbc-url.py)"
```

Save these values privately before leaving the setup terminal. The JDBC helper validates endpoint fields and percent-encodes the database name. The production entry point and migration command both reject URL userinfo, query properties and fragments: pgJDBC URL properties could otherwise override separately configured TLS settings. Both paths use `verify-full`, the downloaded CA, a 5-second connection timeout and a 15-second socket timeout.

## Roles, migrations and seed

Run the bootstrap with Cloud administrator credentials:

```bash
psql -X -v ON_ERROR_STOP=1 \
  -v migrator_password="$MIGRATOR_PASSWORD" -v app_password="$APP_PASSWORD" \
  -f sql/bootstrap.sql
java -Djava.util.logging.manager=org.jboss.logmanager.LogManager \
  -cp 'target/quarkus-app/app/*:target/quarkus-app/lib/main/*:target/quarkus-app/lib/boot/*' \
  example.Migrate
PGUSER=revision_migrator PGPASSWORD="$MIGRATOR_PASSWORD" \
  psql -X -v ON_ERROR_STOP=1 -f sql/seed.sql
```

`revision_owner` cannot log in. The separate Flyway command connects as `revision_migrator`, assumes that owner role and runs versioned SQL without starting HTTP or ORM. Repeating migrations executes zero new migrations; repeating the seed keeps exactly two accounts. Flyway clean is disabled.

`revision_app` can read accounts, insert documents, update only their title/draft/publication fields, and insert/read revisions. It cannot update or delete existing revision content, change document ownership, create schema objects or assume the owner role. Its sessions have an 8-second statement timeout, 3-second lock timeout and 10-second idle transaction timeout. The Agroal pool admits at most four connections and waits up to three seconds for acquisition. These are separate limits, not an HTTP latency guarantee.

This is a trusted shared database role: account authorization is enforced by the API, not row-level security. Anyone holding runtime database credentials can bypass the API's version workflow. Protect those credentials.

## Start the API

Open a new terminal that has **not** sourced setup credentials. Save/export only the runtime values shown in `.env.example` in a private `app.env`; set `PGUSER=revision_app` and `PGPASSWORD` to `APP_PASSWORD`. The file must contain real 64-character lowercase hex tokens, not the example placeholders.

```bash
set -a
source "$HOME/document-private/app.env"
set +a
python3 checks/launch.py
```

The launcher gives the production JVM an explicit runtime-only environment, excluding administrator and migration credentials. It listens on `127.0.0.1:8080`. `/live` is public process liveness; it is not a database readiness test. Every `/documents` route requires native Quarkus authentication. Serve through an appropriately configured HTTPS gateway before exposing it outside a trusted machine.

The first token maps to `00000000-0000-0000-0000-000000000001`; the second maps to the account ending in `002`. Tokens are server-managed demo credentials, with no user signup or token rotation endpoint.

## Try a draft and publication

In another runtime terminal, load `app.env` with exports as above:

```bash
curl -sS http://127.0.0.1:8080/documents \
  -H "Authorization: Bearer $ACCOUNT_001_TOKEN" -H 'Content-Type: application/json' \
  -d '{"title":"Release guide","body":"First public text"}'
```

Copy the response `id` to `DOCUMENT_ID`. It starts at draft revision 1 with no published selection and publication version 0.

```bash
export DOCUMENT_ID=YOUR_RETURNED_DOCUMENT_ID
curl -sS "http://127.0.0.1:8080/documents/$DOCUMENT_ID/publication" \
  -H "Authorization: Bearer $ACCOUNT_001_TOKEN" -H 'Content-Type: application/json' \
  -d '{"expectedPublicationVersion":0,"revision":1}'
curl -sS "http://127.0.0.1:8080/documents/$DOCUMENT_ID/revisions" \
  -H "Authorization: Bearer $ACCOUNT_001_TOKEN" -H 'Content-Type: application/json' \
  -d '{"expectedDraftRevision":1,"title":"Release guide","body":"Unpublished changes"}'
curl -sS "http://127.0.0.1:8080/documents/$DOCUMENT_ID/draft" \
  -H "Authorization: Bearer $ACCOUNT_001_TOKEN"
curl -sS "http://127.0.0.1:8080/documents/$DOCUMENT_ID/published" \
  -H "Authorization: Bearer $ACCOUNT_001_TOKEN"
```

The draft returns revision 2; the published route still returns revision 1. `GET /documents/{id}/revisions/{number}` selects a historical snapshot. History returns the latest 100 revision summaries in numeric descending order; the document list returns the latest 20 summaries ordered by creation time and UUID. These bounded lists do not provide pagination. DTOs expose content only through the selected content routes.

## Transaction and retry behavior

Each edit locks the document using an account-and-document predicate inside an injected CDI `@Transactional` service. It compares the expected draft, inserts and flushes the new snapshot, then advances and flushes the draft pointer. The HTTP resource receives the result only after the transaction interceptor commits. A failed later write or deferred constraint at commit rolls back everything.

Publishing uses the same scoped lock, checks that the selected revision belongs to this document, then advances a separate publication version. Composite foreign keys enforce same-document targets for both pointers independently of application queries.

A repeated publication selecting the **current** published revision returns that selection unchanged when its expected version is either the current version or immediately preceding version. This makes an immediate retry after a lost acknowledgment safe; it is not a durable request-ID ledger. Older versions and competing different selections return 409: refetch and decide again. Editing also returns 409 on stale expectations. Create is not idempotent, and a lost create acknowledgment cannot be blindly retried without risking another document. A 503 signals uncertainty; inspect/refetch durable state before choosing a retry.

Titles are 1–120 UTF-16 code units; bodies are 1–16,000, both nonblank. Bodies permit newline, carriage return and tab; other control characters, NUL and unpaired surrogates are rejected. Revision/version fields are JSON integers between 1 and 1,000,000,000, except publication expectations also allow zero. Unknown fields, duplicate keys, concatenated JSON objects and numeric/string coercions fail. Requests are capped at 64 KiB. Foreign account documents and missing revisions return 404.

## Cloud acceptance checks

After starting the production API, use a **separate setup/test terminal**. Export the endpoint/CA/runtime fields from `app.env`, then explicitly export `TEST_MIGRATOR_PASSWORD` from the privately saved migration password. The helpers need the owner role only to install/remove synthetic failure triggers; the running API still has only runtime credentials.

```bash
export TEST_MIGRATOR_PASSWORD=YOUR_MIGRATION_PASSWORD
export EVIDENCE_DIR="$HOME/document-private"
python3 checks/cloud-controls.py
```

The suite performs actual HTTP contention, strict parsing and ownership controls, draft/published separation, repeated publication, PostgreSQL FK/permission failures, an after-insert rollback, and a deferred FK failure at commit. It leaves a synthetic document for restart verification. Save the production JVM PID in `$EVIDENCE_DIR/server.pid` when starting it if you will run the restart helper:

```bash
python3 checks/launch.py > "$EVIDENCE_DIR/server.log" 2>&1 &
printf '%s\n' "$!" > "$EVIDENCE_DIR/server.pid"
python3 checks/security-restart.py
```

Start only one listener; stop an existing foreground listener before the background launch. The restart helper uses the actual packaged application for wrong-CA and wrong-hostname checks, requires specific pgJDBC diagnostics, asserts the original process exited, then reads persisted draft/published state from a different JVM. Private logs contain infrastructure details; keep them out of source control.

Verified on 2 October 2026: native clean package (three tests), clean Flyway migration/repeat and seed/repeat, real HTTP edit/publication races, rollback/commit failure controls, restricted grants, TLS controls and production process restart. See the companion article's evidence discussion; the article remains a local draft until publication.

## Cleanup

Restore the **Cloud administrator** credentials in a setup terminal before optional schema removal; `app.env` selects the restricted runtime role. Schema removal is destructive and only for your disposable fixture:

```bash
export PGUSER=YOUR_CLOUD_ADMIN_USER PGPASSWORD=YOUR_CLOUD_ADMIN_PASSWORD
psql -X -v ON_ERROR_STOP=1 -c 'DROP SCHEMA revision_api CASCADE;'
```

Stop the application and delete only the service you created:

```bash
clickhousectl cloud postgres delete "$PG_ID" --org-id YOUR_ORG_ID
clickhousectl cloud postgres list --org-id YOUR_ORG_ID
```

Wait until the exact ID is absent; Postgres deletion does not accept `--force`. Remove private credentials and certificates when no longer needed. Retain source and sanitized evidence.

## References

- [Panache queries, locks and transactions](https://quarkus.io/guides/hibernate-orm-panache/)
- [Quarkus security customization](https://quarkus.io/guides/security-customization/)
- [Quarkus Flyway](https://quarkus.io/guides/flyway/)
- [pgJDBC TLS verification](https://jdbc.postgresql.org/documentation/ssl/)
- [ClickHouse Managed Postgres overview](https://clickhouse.com/docs/products/managed-postgres/overview)
