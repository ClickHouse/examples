# Team invitations with Swift and Postgres

A small JSON API where a seeded team administrator invites an existing seeded user. The recipient accepts a 256-bit secret once, committing an invitation state change and a membership together. Matching acceptance retries return the original membership. This example uses ClickHouse Managed Postgres (public beta), Swift 6.4.0, stable Vapor 4.122.2, Fluent 4.13.0, FluentPostgresDriver 2.14.0 and PostgresNIO 1.33.1. Package.resolved pins the full stable dependency graph. Live validation used PostgreSQL 18.6 on native Ubuntu 24.04 ARM64.

This is an API demonstration with seeded identities and environment bearer credentials. There is no signup, email delivery, email verification, browser session, team creation route or real identity provider. Each credential identifies exactly one existing user through Vapor's native AsyncBearerAuthenticator and guard middleware. The shared database role trusts the API to apply user scope; its grants do not provide independent tenant isolation. The server listens on loopback.

## Workflow

- An administrator issues an invitation for a named recipient on their own team. Only SHA256 of the cryptographically random secret is stored. The raw secret appears only in the creation response. Never place it in a URL or log it. If that response is lost, revoke and reissue; creation has no retained request ID.
- Acceptance locks the invitation row, verifies its authenticated recipient and secret, then reads clock_timestamp() after acquiring the lock. Pending invitations expire according to database time. Acceptance updates state and inserts membership using the same Fluent transaction handle.
- Consumed matching retries return the original membership with 200, even after expiry. A new acceptance returns 201; a lost acknowledgment can therefore lead to 200 on retry. A wrong recipient or secret gets 404. Revoked invites get 409; expired pending invites get 410.
- Revoke takes the same row lock. If acceptance commits first, revoke gets 409 and cannot remove membership. If revoke commits first, acceptance gets 409. Repeating revoke returns the revoked metadata.

Unique(team_id,user_id) prevents duplicate membership independently of API serialization. A deferred composite foreign key ties accepted_membership_id,team_id,recipient_id to that exact membership. It permits state-first insertion inside the transaction and enforces correspondence at commit. Separate invitations to the same recipient/team can race on this unique constraint: one succeeds, the other gets 409 and rolls back. SQLKit is used narrowly for row locks, database time, constraints and grants; all values in operational SQL are bound parameters.

List routes return explicit DTOs, never database models or digests. They accept limit 1–50 (default 20) and an optional after UUID; results sort by UUID ascending with a strict greater-than cursor. This is a live keyset list, without a snapshot: inserts behind the cursor are not seen on an ongoing traversal. Every list re-applies its administrator or authenticated recipient scope. JSON bodies are limited to 4 KiB, unknown input fields are rejected, and invitation TTL is 1–1440 minutes.

## Native prerequisites

Install the official stable [Swift 6.4.0 Linux toolchain](https://www.swift.org/install/linux/ubuntu/24_04/) and its documented Ubuntu 24.04 dependencies on your Linux machine. All installation, package resolution, compilation and tests for this example ran under native /home/al on ARM64; nothing was compiled on macOS. You also need native OpenSSL, GNU timeout and psql for setup/live tests, and the current [clickhousectl CLI](https://github.com/ClickHouse/clickhousectl).

```bash
cd applications/team-invitations
swift package resolve
swift build --jobs 2
swift test --jobs 2
```

Builds and unit tests require no database credentials. Keep Package.resolved; no Vapor 5 prerelease enters the graph.

## Create the Cloud service

Authenticate clickhousectl with your Cloud organization API credentials. This service is billable; the fixture below selects a modest supported AWS shape and no HA. Use current CLI help if your region or account differs.

```bash
clickhousectl cloud postgres create --name team-invitations-demo \
  --provider aws --region us-east-1 --size c6gd.large --postgres-version 18 --ha-type none \
  --json > postgres-create.json
chmod 600 postgres-create.json
# Save the returned ID and password privately. get never returns the password.
clickhousectl cloud postgres get YOUR_POSTGRES_ID --json
# Repeat get until state is running.
mkdir -p .deployment
chmod 700 .deployment
clickhousectl cloud postgres certs get YOUR_POSTGRES_ID --output .deployment/cloud-ca-bundle.pem
```

The original authenticated CA bundle must be retained. The tested bundle contained two roots with the same subject but different keys; full-bundle NIOSSL chain selection failed while OpenSSL verified the endpoint. The setup helper selects exactly one candidate FROM the authenticated bundle that verifies the received leaf and endpoint hostname. It first uses a fully verified OpenSSL handshake bounded by GNU timeout to 20 seconds and refuses zero or multiple matches. It never treats a peer certificate as a trust anchor and does not choose by bundle order.

```bash
export PGHOST=YOUR_MANAGED_ENDPOINT
export PGPORT=5432
scripts/select-trust-root.sh .deployment/cloud-ca-bundle.pem .deployment/selected-root.pem
export PGSSLROOTCERT="$PWD/.deployment/selected-root.pem"
export PGDATABASE=postgres PGSSLMODE=verify-full
```

Runtime PostgresNIO still requires TLS, full CA and hostname verification, and PGHOST as tlsServerName for SNI. CA rotation requires fetching a fresh authenticated bundle and rerunning selection before restarting. Failed selection or failed TLS must be investigated; there is no trust fallback. The helper is a setup operation, not a background rotation service.

## Separate schema and runtime roles

In this setup shell, use the service's returned administrator credentials. Generate distinct strong passwords and retain them in a private passwords.env (exported values), separate from runtime app.env.

```bash
export PGUSER=postgres
read -rs -p 'Cloud administrator password: ' PGPASSWORD; echo
export PGPASSWORD
export INVITES_MIGRATOR_PASSWORD=$(openssl rand -hex 32)
export INVITES_APP_PASSWORD=$(openssl rand -hex 32)
psql -X -v migrator_password="$INVITES_MIGRATOR_PASSWORD" \
  -v app_password="$INVITES_APP_PASSWORD" -f scripts/bootstrap.sql
export PGUSER=invites_migrator PGPASSWORD="$INVITES_MIGRATOR_PASSWORD"
.build/debug/Invitations migrate --yes
.build/debug/Invitations seed
```

bootstrap.sql is intentionally one-time for an empty dedicated service. invites_owner cannot log in; the migrator assumes it only for schema/seed operations. Runtime has SELECT on the four app tables, INSERT on invitations/memberships, only state-transition UPDATE columns on invitations, and UPDATE(id) on teams to permit its scoped row lock. Runtime cannot create tables, change digests/expiry/identities, delete memberships or create users. Runtime startup performs no migrations.

For a disposable fixture, migrate --yes can be repeated; migrate --revert --yes drops all application tables and data, followed by migrate --yes and seed. Do not run destructive reversal on data you need. Repeating seed preserves existing identities and state.

The seeded users are 00000000-0000-4000-8000-000000000001 through 004. North team a0000000-0000-4000-8000-000000000001 belongs to user 001; South team b0000000-0000-4000-8000-000000000001 belongs to user 002. Administrator identities are fixed in this example.

## Start and try the API

Start a **fresh shell** before loading app.env so setup credentials are not inherited. Copy .env.example to a private exported environment file outside source control. Set its endpoint/CA and runtime password. USER_TOKENS maps seeded UUIDs to distinct 32–256 character credentials; generate each with openssl rand -hex 32. The server rejects missing/duplicate/weak mappings and configured users absent from the seed. Treat this as a bounded test authentication scheme.

```bash
set -a
source /absolute/private/app.env
set +a
cd applications/team-invitations
scripts/run-runtime.sh
```

The launcher explicitly passes only runtime fields to the server. It uses two event loops and at most two connections per loop (maximum four overall). Pool acquisition is bounded to 10 seconds; connection setup to 5 seconds and SQL statements to 15 seconds. These are individual limits, not an overall HTTP latency guarantee. Requests that reach a database failure return 503 with a generic message; retry acceptance using the same invitation and secret.

In another shell, supply only the appropriate bearer credentials. Capture creation privately so its single secret response is not printed or logged:

```bash
export ADMIN_TOKEN=YOUR_USER 001_CREDENTIAL
export RECIPIENT_TOKEN=YOUR_USER 003_CREDENTIAL
umask 077
curl -fsS -X POST http://127.0.0.1:3000/teams/a0000000-0000-4000-8000-000000000001/invitations \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H 'Content-Type: application/json' \
  -d '{"recipientUserId":"00000000-0000-4000-8000-000000000003","ttlMinutes":60}' > issued.json
# Read invitation.id and secret privately. Send {"secret":"..."} in the POST body:
curl -sS -X POST http://127.0.0.1:3000/invitations/INVITATION_UUID/accept \
  -H "Authorization: Bearer $RECIPIENT_TOKEN" -H 'Content-Type: application/json' \
  --data-binary @acceptance.json
curl -fsS http://127.0.0.1:3000/memberships?limit=20 -H "Authorization: Bearer $RECIPIENT_TOKEN"
# Administrator revocation body is the empty object {}.
```

Routes: POST /teams/:id/invitations, POST /invitations/:id/accept, POST /invitations/:id/revoke, GET /teams/:id/invitations and GET /memberships. Authentication is required for all routes.

## Verify the live fixture

Use an empty migrated/repeatedly seeded fixture and a running API. In a separate **test shell**, explicitly load runtime endpoint/CA/token fields and the separate migration password. The API process remains runtime-only.

```bash
set -a; source /absolute/private/app.env; source /absolute/private/passwords.env; set +a
export TEST_MIGRATOR_PASSWORD="$INVITES_MIGRATOR_PASSWORD"
export TEST_RESTART_FIXTURE=/absolute/private/restart-fixture.json
export TEST_EVIDENCE_DIR=/absolute/private/evidence
python3 checks/cloud.py
python3 checks/focused.py
# After that suite, restart the real executable and replay its private fixture:
scripts/process-restart.sh
```

The suite checks competing accepts, a real accept/revoke race, matching consumed replay after expiry, a separate SQL row lock held past pending expiry, a forced failure after the invitation state update, independent uniqueness/composite FK checks, forbidden runtime operations, ownership, DTOs and input/list limits. The restart helper must prove the original PID is gone before launching its replacement; its child environments include only runtime credentials.

The actual factory's positive TLS control is .build/debug/Invitations tls-check. With a valid PEM containing the other official same-name root as PGSSLROOTCERT it must fail; the selected root succeeds. .build/debug/Invitations tls-check --wrong-hostname must also fail, using the same endpoint with a mismatching validation/SNI name. No certificate verification is disabled for these controls.

## Cleanup

Stop the API, then delete **only your recorded** service ID. Keep no-HA fixtures only long enough for acceptance testing.

```bash
clickhousectl cloud postgres delete YOUR_POSTGRES_ID
clickhousectl cloud postgres list --json
# Verify your recorded ID is absent. Postgres delete has no --force option.
```

If retaining a dedicated service but removing the example, restore administrator credentials explicitly in a setup shell before any cleanup:

```bash
export PGUSER=postgres
read -rs -p 'Cloud administrator password: ' PGPASSWORD; echo
export PGPASSWORD PGSSLMODE=verify-full
psql -X -v ON_ERROR_STOP=1 -c 'DROP SCHEMA invites CASCADE; REVOKE invites_owner FROM invites_migrator; DROP OWNED BY invites_app, invites_migrator, invites_owner; DROP ROLE invites_app, invites_migrator, invites_owner;'
```

The [Managed Postgres documentation](https://clickhouse.com/docs/products/managed-postgres/overview), [Fluent transaction guide](https://docs.vapor.codes/fluent/transaction/) and [Vapor authentication guide](https://docs.vapor.codes/security/authentication/) explain the underlying services and framework primitives.
