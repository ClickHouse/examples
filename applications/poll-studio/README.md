# Poll studio

A trusted local R/Shiny workbench creates a fictional poll, records synthetic responses, draws stored counts, refreshes another browser's changes and closes the poll. ClickHouse Managed Postgres (public beta) stores the durable poll, choices and responses. Participant codes deduplicate submissions; they are not authenticated identities. All operators share authority. Use made-up labels/codes and no personal information.

## Boundaries and behavior

- Create stores a question and two through eight distinct choices in one transaction. Questions allow 1–200 characters, choices 1–80 after trimming; control characters are rejected. The multiline form input is capped at 1,024 characters.
- Respond locks the poll row, checks a saved poll/code response first, then open state, the 10,000-response application cap and the choice. It increments the counter and inserts the response using the same transaction connection.
- Matching retries return the original response, including after closure or the response cap. A different choice under the same normalized code conflicts. Codes are trimmed and uppercased, with 3–32 ASCII letters, digits, underscores or hyphens.
- Close takes the same parent lock. Counts query the stored rows; reactive values only invalidate reads. Refresh explicitly loads another browser's committed changes; there is no live push.
- The list contains the newest 100 polls ordered by creation time and ID; no pagination. A summary returns at most eight grouped counts, not all participant codes or response records. Charts show counts, without inference claims.

The composite response foreign key enforces poll/choice membership. A unique poll/code constraint backs repeat safety. Runtime grants deny edits/deletes to existing choices/responses and deny DDL. A trusted holder of runtime database credentials can still append choices directly and update the poll counter or closed timestamp; complete choice-set creation, monotonic closure and the true response cap depend on the application's transaction/locking protocol. The role is shared and is not a per-user security boundary. This example does not claim a publicly writable survey service.

The standalone Shiny server checks `session$request$HTTP_ORIGIN` from the actual WebSocket request against a fixed configured loopback origin before registering database observers. Missing/foreign Origins close the session. The trusted value is not derived from Host. This is browser cross-site protection, not authentication or a deployment access-control replacement.

## Native prerequisites and restore

Pinned runtime: R 4.6.1. The complete `renv.lock` pins Shiny 1.14.0, httpuv 1.6.17, DBI 1.3.0, RPostgres 1.4.10, pool 1.0.5 and their dependencies. Standard `.Rprofile`, `renv/activate.R` and settings bootstrap the project; package libraries and caches are not committed. renv does not install R or OS libraries.

On Ubuntu 24.04 ARM64, install native build/client/graphics dependencies before compiling R or restoring packages:

```bash
sudo apt-get update
sudo apt-get install -y build-essential gfortran curl ca-certificates \
  libcurl4-openssl-dev libssl-dev libxml2-dev libpq-dev libreadline-dev \
  libpcre2-dev libbz2-dev liblzma-dev zlib1g-dev libuv1-dev \
  libcairo2-dev libpango1.0-dev libpng-dev libjpeg-dev libtiff-dev cmake \
  postgresql-client xz-utils
```

Install the pinned R release using your supported runtime installer or compile the official source. A native prefix avoids changing another runtime:

```bash
curl -fSLO https://cran.r-project.org/src/base/R-4/R-4.6.1.tar.gz
tar -xzf R-4.6.1.tar.gz
cd R-4.6.1
./configure --prefix="$HOME/R" --with-x=no --enable-R-shlib
make -j2
make install
export PATH="$HOME/R/bin:$PATH"
```

From this application directory:

```bash
Rscript -e 'renv::restore(prompt = FALSE)'
Rscript -e 'stopifnot(capabilities("png"), capabilities("cairo"))'
Rscript test/domain.R
Rscript -e 'for (p in c("app.R", "run.R", list.files("R", full.names=TRUE))) parse(p)'
```

To prove restore into a separate fresh project/library/cache, initialize the project before restoring its lock. Initialization activates renv's isolated library/sandbox; an uninitialized `--vanilla` session can otherwise consider global packages sufficient.

```bash
export RESTORE_PROJECT=/absolute/path/fresh-project
export SOURCE_LOCK="$PWD/renv.lock"
RENV_PATHS_CACHE=/absolute/path/fresh-cache Rscript --vanilla -e '
  project <- Sys.getenv("RESTORE_PROJECT")
  renv::init(project=project, bare=TRUE)
  file.copy(Sys.getenv("SOURCE_LOCK"), file.path(project, "renv.lock"), overwrite=TRUE)
  renv::restore(project=project, prompt=FALSE)
  for (p in c("shiny", "DBI", "RPostgres", "pool")) loadNamespace(p)'
```

## Create a dedicated Cloud service

Use authenticated clickhousectl. Verify region/shape availability and costs before provisioning. The example uses AWS us-east-1, c6gd.large, PostgreSQL18 and no HA:

```bash
export ORG_ID=your-organization-id
clickhousectl cloud postgres create --org-id "$ORG_ID" \
  --name poll-studio --provider aws --region us-east-1 --size c6gd.large \
  --pg-version 18 --ha-type none --json > /private/path/service.json
chmod 600 /private/path/service.json
export SERVICE_ID=your-returned-service-id
clickhousectl cloud postgres get "$SERVICE_ID" --org-id "$ORG_ID" --json
```

Repeat get until the state is running; retain the create receipt's credentials privately. Download the service CA:

```bash
clickhousectl cloud postgres certs get "$SERVICE_ID" --org-id "$ORG_ID" \
  --output /private/path/cloud-ca.pem
```

Running services incur charges. No analytical ClickHouse service is used.

## Empty-schema setup and seed

Create a private setup environment file with the receipt's administrator credentials and distinct random role passwords of at least 24 characters:

```dotenv
PGHOST=your-service-hostname
PGPORT=5432
PGDATABASE=postgres
PGSSLMODE=verify-full
PGSSLROOTCERT=/absolute/path/cloud-ca.pem
ADMIN_USER=receipt-username
ADMIN_PASSWORD=receipt-password
MIGRATION_PASSWORD=distinct-random-owner-password
APP_PASSWORD=distinct-random-runtime-password
```

Export the fields, bootstrap as administrator, and migrate/seed as schema owner:

```bash
set -a; source /private/path/setup.env; set +a
export PGUSER="$ADMIN_USER" PGPASSWORD="$ADMIN_PASSWORD"
psql -X -f sql/bootstrap.sql
export PGUSER=polls_migration PGPASSWORD="$MIGRATION_PASSWORD"
psql -X -f sql/migrate.sql
psql -X -f sql/seed.sql
```

Bootstrap runs once and creates the owned schema explicitly; the owner needs no database CREATE. It revokes PUBLIC database CREATE/TEMP and public-schema CREATE for this dedicated database. Migration version1 creates identity keys, constraints/indexes and scoped grants. Repeat migration and seed to check reproduction. The seed adds a fictional workshop poll without responses. Runtime receives select/insert, sequence usage and updates only to `response_count`/`closed_at`; no question edit, row delete, response/choice edit or schema-history access. Startup performs no migration or seed.

## Start the local workbench

Create a private runtime file from [.env.example](.env.example), with only runtime credentials and connection/origin fields:

```bash
set -a; source /private/path/runtime.env; set +a
unset ADMIN_USER ADMIN_PASSWORD MIGRATION_PASSWORD APP_PASSWORD
export LANG=C.UTF-8 # Tested Ubuntu Unicode locale
Rscript run.R
```

Open exactly `http://127.0.0.1:4000`, matching `APP_ORIGIN`. The listener binds loopback. A different port requires matching PORT and fixed loopback APP_ORIGIN. Database options always use libpq `sslmode=verify-full`, the downloaded CA, a hostname, 10-second connect timeout, 5-second statement timeout and 3-second lock timeout. Bigint IDs map to character values, so they never pass through imprecise doubles; bounded counts are cast to integer.

The finite pool holds one through four connections and closes on app stop. Every multi-write operation uses `pool::poolWithTransaction(db, function(conn) ...)` and only that callback connection. No connection or transaction remains checked out across browser input. Normal R database work in one Shiny process is synchronous; two sessions alone do not prove independent transaction contention.

Expected validation/conflict errors appear as understandable notifications. Unexpected errors stay generic; Shiny error sanitization remains enabled. Text/radio/table labels use framework escaping. The chart renders horizontal bars natively with PNG/Cairo and abbreviates labels beyond 18 characters; the table retains full labels. This is a loopback demonstration, not a public deployment recipe; deployed use needs authentication, access controls, HTTPS and operational limits.

## Acceptance against the dedicated Cloud fixture

After setup, switch to runtime credentials but retain owner/admin fields only in this test shell:

```bash
export PGUSER=polls_app PGPASSWORD="$APP_PASSWORD"
export EVIDENCE_DIR=/private/path/evidence
mkdir -p "$EVIDENCE_DIR"
Rscript test/cloud.R
```

The suite uses separate R worker processes for same-code contention and held-lock response/close ordering, observing actual blocked database sessions. Workers use longer timeouts only for controlled test barriers. Owner-only temporary rejecting triggers force failures after earlier writes, then are removed; no runtime privilege changes are needed. The cap test accelerates the stored counter with the owner and restores it afterward. Foreign-choice and duplicate-key checks exercise actual database constraints. TLS tests use a valid unrelated CA and resolve the real endpoint address with a deliberately mismatched libpq hostname, then prove the ordinary connection succeeds.

Optional browser acceptance uses isolated Node24.21.0, Playwright1.63.0 and ws8.22.0 dependencies. The harness resolves Rscript through PATH; set RSCRIPT to an explicit executable if needed:

```bash
export BROWSER_DIR=/private/path/browser-dependencies
mkdir -p "$BROWSER_DIR"
npm --prefix "$BROWSER_DIR" install --save-exact playwright@1.63.0 ws@8.22.0
"$BROWSER_DIR/node_modules/.bin/playwright" install --with-deps chromium
cp test/browser.mjs "$BROWSER_DIR/browser.mjs"
export APP_DIR="$PWD" EVIDENCE_DIR=/private/path/evidence
# Use runtime.env only; the harness does not receive elevated credentials.
node "$BROWSER_DIR/browser.mjs"
```

It exercises two real contexts, create/respond/chart/refresh/close, replay/conflict, second-poll selection, escaped labels, eight maximum-length labels on mobile, a foreign-browser Origin and a missing-Origin WebSocket with independent stored-row observations, and confirmed original-process exit/restart. Evidence stays outside the source tree.

## Cleanup

Stop the app first (Ctrl+C). A destructive dedicated-fixture reset explicitly restores administrator credentials:

```bash
set -a; source /private/path/setup.env; set +a
export PGUSER="$ADMIN_USER" PGPASSWORD="$ADMIN_PASSWORD"
psql -X -f sql/cleanup.sql
```

Cleanup removes only the application schema and two roles; PUBLIC privilege revocations remain. No production downgrade is supplied. Delete your billable fixture by its recorded exact ID and verify absence after asynchronous deletion:

```bash
clickhousectl cloud postgres delete "$SERVICE_ID" --org-id "$ORG_ID"
clickhousectl cloud postgres list --org-id "$ORG_ID" --json
```

Deletion destroys that service's data; preserve needed evidence first.

## Primary references

- [One-connection pool transaction callback](https://rstudio.github.io/pool/reference/poolWithTransaction.html)
- [RPostgres libpq options and bigint mapping](https://rpostgres.r-dbi.org/reference/Postgres.html)
- [renv restore and runtime/system dependency limits](https://rstudio.github.io/renv/articles/renv.html)
- [Shiny1.14.0 session WebSocket request source](https://github.com/rstudio/shiny/blob/v1.14.0/R/shiny.R)
- [Standalone Shiny runApp](https://shiny.posit.co/r/reference/shiny/latest/runapp.html)
- [ClickHouse Managed Postgres setup](https://clickhouse.com/docs/products/managed-postgres/quickstart)
