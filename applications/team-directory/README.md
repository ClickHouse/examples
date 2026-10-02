# Team directory

Sign in, find a colleague, and maintain your own profile backed by [ClickHouse Managed Postgres](https://clickhouse.com/docs/products/managed-postgres/). This Nuxt application uses Vue, Nitro server routes, Knex, node-postgres and nuxt-auth-utils. Two main screens cover the directory and your profile; sign-in uses synthetic seeded accounts with an operator-provided password. No sign-up, password reset, uploads or external identity provider is included.

Profile fields and selected skills save in one transaction. The server derives the owner from a sealed session cookie and requires the revision the editor saw. Competing saves cannot silently overwrite each other. Skills come from a controlled seeded list; a composite membership key, foreign keys and a parent-locking trigger enforce distinct, existing skills and a maximum of six.

## Behavior and boundaries

- Display name: 1–80 characters after trimming. Biography: at most 1,000; location: at most 80. All are strings without Unicode control characters, including newlines. The biography is a single paragraph. Values remain ordinary escaped text in Vue.
- A save replaces the complete skill set, increments the profile revision once, and commits all fields/memberships together. Unknown skill IDs roll back an earlier profile update and membership deletion. Stale saves return 409 and retain local edits; explicitly reload and review before trying again.
- Profile reads lock the parent briefly for a consistent fields/skills result. Directory reads use a repeatable-read transaction, 12 profiles per page, deterministic UUID tie-breakers, page 1–1,000, bounded search/location strings and allowlisted name/recent ordering. `%`, `_` and backslash are literal search characters; an unknown skill filter produces no matches.
- Any active signed-in account may read the directory. Only the authenticated owner may write a profile. UUID paths are validated and canonicalized; extra owner fields are rejected. Browser controls are conveniences, with independent server validation.
- nuxt-auth-utils uses scrypt password verification and sealed cookie sessions. The payload contains only user ID and sign-in time, with a two-hour expiry, HttpOnly, SameSite=Lax and Secure by default. The server rechecks account existence/active state on authenticated requests. Logout empties the browser's cookie; **a previously copied valid cookie can still be replayed until expiry**, unless the account is disabled/deleted or the sealing key changes. There is no per-session server revocation or password-change revocation mechanism.
- Every unsafe API request, including the module's DELETE logout endpoint, requires an exact Origin matching the configured canonical origin; cross-site Fetch Metadata is rejected. Trust never comes from Host or forwarded headers. Browser same-origin fetch supplies Origin automatically. JSON mutation bodies are bounded to 8 KiB, including chunked requests.
- Sign-in allows 12 attempts per direct socket IP per three minutes, with at most 1,000 active limiter entries. This in-memory limiter resets on restart and is not distributed. Behind a proxy, requests share the proxy's socket IP; configure a separate trusted proxy/authentication boundary for a larger deployment. The example binds to loopback and does not trust forwarded IP headers.

The server-only lazy Knex pool uses at most four connections. No pool or database configuration is imported by client code. Runtime grants restrict operations, but the shared runtime role remains trusted: it can see password hashes and edit profiles through direct SQL. Application ownership/revision checks are not PostgreSQL row-level isolation.

## 1. Native Linux installation

Use Node **24.21.0**, npm, PostgreSQL client tools, jq and OpenSSL. Verified on Ubuntu 24.04 arm64. Clone this repository and enter `applications/team-directory`, in a native Linux filesystem:

```sh
sudo apt-get update
sudo apt-get install -y --no-install-recommends postgresql-client git curl jq openssl
node --version
npm ci
npm test
npm run typecheck
npm run build
```

The lockfile pins the complete dependency graph. Nuxt 4.5.2, Vue 3.5.43, Nitro 2.13.4, Knex 3.3.0, pg 8.23.1 and nuxt-auth-utils 0.5.30 were verified together. Build/unit/type checks do not need Cloud credentials. `npm run format:check` checks the source with Prettier.

The dependency audit on 2 October 2026 reports an unpatched [node-forge RSA verification advisory](https://github.com/advisories/GHSA-86w9-cpqp-85rv), propagated through Nuxt's `listhen` development HTTPS tooling. That package is absent from the tested `.output/server` deployment; this app uses Node's TLS for Postgres and does not enable development HTTPS. Do not interpret this as a clean audit or use `npm audit fix --force` to downgrade Nuxt incompatibly. Recheck upstream before deployment. Playwright is pinned to patched 1.55.1.

## 2. Create a dedicated Cloud service

Install [clickhousectl](https://clickhouse.com/blog/clickhousectl-v0-2-0-postgres-clickpipes-more), authenticate with an Admin API key, and inspect your organization. Interactive authentication avoids secrets in command arguments:

```sh
curl -fsSL https://clickhouse.com/cli | sh
export PATH="$HOME/.local/bin:$PATH"
clickhousectl cloud auth login --interactive
clickhousectl cloud auth status
clickhousectl cloud org list
umask 077
mkdir -p .deployment
```

Create private `.deployment/resources.env` containing your organization and currently supported region/size:

```dotenv
CH_ORG_ID=YOUR_ORGANIZATION_UUID
CLOUD_REGION=us-east-1
PG_SIZE=c6gd.large
```

The fixture used AWS us-east-1, `c6gd.large`, Postgres 18 and no HA. Verify [current availability](https://clickhouse.com/docs/products/managed-postgres/) and [pricing](https://clickhouse.com/pricing) first. Compute/storage incur charges; stopping the Nuxt process does not delete or stop the database.

```sh
source .deployment/resources.env
clickhousectl cloud postgres create --org-id "$CH_ORG_ID" \
  --name team-directory-example --provider aws --region "$CLOUD_REGION" \
  --size "$PG_SIZE" --pg-version 18 --ha-type none --json \
  > .deployment/postgres-create.json
PG_SERVICE_ID="$(jq -er '.id' .deployment/postgres-create.json)"
```

Save that service ID in `resources.env`. Creation returns the initial password once; keep the receipt private. If creation is interrupted, inspect the list before retrying. Repeat `get` until `state` is `running`, then retrieve the CA:

```sh
clickhousectl cloud postgres get "$PG_SERVICE_ID" --org-id "$CH_ORG_ID" --json
clickhousectl cloud postgres certs get "$PG_SERVICE_ID" --org-id "$CH_ORG_ID" \
  --output .deployment/ca.pem
```

Append the actual returned direct `PGHOST`, `PGPORT=5432`, `PGDATABASE=postgres`, and absolute Linux `PGSSLROOTCERT` path to `resources.env`. Credentials and CA must exist in the environment running Node, not just your laptop.

## 3. Bootstrap schema and separate roles

Use a dedicated service: the script creates new fixed role/schema names and revokes public CREATE/TEMP privileges. It deliberately fails if those names already exist. Generate passwords once, preserving the file on retries:

```sh
cat > .deployment/passwords.env <<PASSWORDS
PG_MIGRATION_PASSWORD=Aa1_$(openssl rand -hex 24)
PG_APP_PASSWORD=Aa1_$(openssl rand -hex 24)
DEMO_PASSWORD=Aa1_$(openssl rand -hex 16)
PASSWORDS
set -a
source .deployment/resources.env
source .deployment/passwords.env
set +a
export PGSSLMODE=verify-full
export PGUSER="$(jq -er '.username' .deployment/postgres-create.json)"
export PGPASSWORD="$(jq -er '.password' .deployment/postgres-create.json)"
psql -X -v ON_ERROR_STOP=1 -f scripts/bootstrap.sql
unset PGPASSWORD
```

Run migrations, seed and grants in a separate subshell:

```sh
(
  export PGUSER=directory_owner PGPASSWORD="$PG_MIGRATION_PASSWORD"
  npm run db:migrate
  npm run db:seed
  psql -X -v ON_ERROR_STOP=1 -f scripts/grants.sql
)
```

The seed expects no users and creates 16 synthetic colleagues and eight skills. Alex (`alex@example.test`) and Sam (`sam@example.test`) use `DEMO_PASSWORD`; the other fixture accounts use the same password. These are demonstration identities, not real customer records. Production account provisioning/individual passwords is an operator task outside this example.

Knex records migrations in the `directory` schema. On an empty development fixture, verify `npm run db:migrate`, `npm run db:rollback`, `npm run db:migrate` **before seeding/grants**; rollback destroys domain data. Future changes need a new migration and reviewed grants.

`directory_owner` owns the schema. `directory_app` can read users/skills/memberships, update only profile columns/revision/time, and insert/delete memberships. It cannot create tables, edit email/password/active state or change skills. No schema owner or Cloud API credentials belong in the runtime environment.

## 4. Start and use the production build

Copy `.env.example` to a private `.deployment/runtime.env`, supplying the runtime login/password and a random, stable sealing secret (at least 32 characters). node-postgres receives separate fields and the CA with `rejectUnauthorized: true`; default Node certificate checks verify the hostname. Avoid connection URI SSL parameters, which can override supplied TLS options.

For **loopback HTTP only**, set `NUXT_APP_ORIGIN=http://127.0.0.1:3000`, `NUXT_SESSION_SECURE=false` and `NUXT_SESSION_COOKIE_SECURE=false`. For HTTPS deployment, keep both secure flags true, supply the canonical HTTPS origin, and put a correctly configured proxy in front of the loopback listener. HTTP public exposure is outside this example's scope.

Start from a fresh runtime-only shell, with the same sealing key on every restart:

```sh
set -a
source .deployment/runtime.env
set +a
npm run build
node .output/server/index.mjs
```

Visit `http://127.0.0.1:3000`, sign in as Alex, edit name/biography/location and select skills, then save. Search/filter the directory and verify the card. A second tab opened before a save carries its old revision; saving there produces a conflict. `Reload latest` replaces fields only after a successful read; failed reloads retain edits. Unsaved edits are local to the tab.

## 5. Reproduce acceptance

Run checks against a **disposable seeded Cloud fixture** with the production server already listening. Unit/format/type/build checks run in CI without Cloud secrets. Cloud tests modify synthetic profiles and temporarily disable an account. Export separate test credentials in a test-only shell; the server must receive only runtime credentials:

```sh
set -a
source .deployment/runtime.env
source .deployment/passwords.env
set +a
export TEST_OWNER_PGUSER=directory_owner TEST_OWNER_PGPASSWORD="$PG_MIGRATION_PASSWORD"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=wrong-test-ca \
  -keyout .deployment/wrong-ca.key -out .deployment/wrong-ca.pem
export WRONG_CA_PATH="$PWD/.deployment/wrong-ca.pem"
node --test --test-concurrency=1 tests/cloud.test.mjs
```

Ten Cloud cases cover sealed-cookie semantics, foreign/injected ownership, atomic save/rollback after writes, observed simultaneous HTTP lock waits and a single revision winner, deterministic pages/literal search, origin/body bounds, active-account rechecking, runtime permissions/DB membership constraints, CA/hostname TLS controls and sign-in limits. The hostname negative test uses Node's `checkServerIdentity` with a deliberately substituted hostname over the real TLS connection; pg overrides `ssl.servername`, so that flag alone is not the negative control. Application TLS uses the default verifier.

The final rate-limit case intentionally reaches 429. Wait three minutes, or restart the disposable production process, before browser sign-in. Keep the limiter enabled.

```sh
npx playwright install --with-deps chromium
EVIDENCE_DIR=/tmp/team-directory-evidence node tests/browser.mjs
```

The two-account browser helper proves real save/filter/refresh, stale editor rejection, foreign write denial, authenticated SSR, pagination, mobile fit and native logout. Screenshots/traces are saved outside source. Use `BASE_URL` only for a server whose configured origin matches.

For a genuine restart proof, launch the server in the background from a runtime-only shell and save its PID to a private file. Export `DEMO_PASSWORD` in a separate test shell, then run:

```sh
SERVER_PID_FILE=/absolute/path/to/server.pid \
  EVIDENCE_DIR=/tmp/team-directory-evidence node tests/persistence.mjs
```

This helper logs in, records a complete profile, terminates the exact old PID, asserts exit and an absent listener, starts a replacement with an explicit runtime-only environment, and verifies the same cookie/profile/skills/revision. It leaves the replacement running and updates the PID file. It is a Linux acceptance helper, not a process supervisor.

## 6. Cleanup

Stop your app process. Delete **only the service you created**; this destroys its data:

```sh
source .deployment/resources.env
clickhousectl cloud postgres delete "$PG_SERVICE_ID" --org-id "$CH_ORG_ID" --json
clickhousectl cloud postgres list --org-id "$CH_ORG_ID" --json
```

Confirm the exact ID is absent (deletion can be asynchronous). Retain needed evidence privately; remove credential files when no longer needed. No HA, deployment supervisor, distributed limiter or server-side session revocation is claimed here.
