# Operations

Run commands from your checkout using the CLI logins from
[README](../README.md#deploy-your-own-instance). Load your recorded settings and
select your Cloudflare account:

```sh
source .deployment/resources.env
export CLOUDFLARE_ACCOUNT_ID
```

Keep `.deployment/`, the CLI's `.clickhouse/` credentials, and command logs private.

## Inspect and diagnose

```sh
clickhousectl cloud postgres get "$PG_SERVICE_ID" --org-id "$CH_ORG_ID" --json
clickhousectl cloud service get "$CH_SERVICE_ID" --org-id "$CH_ORG_ID" --json
clickhousectl cloud clickpipe get "$CH_SERVICE_ID" "$CLICKPIPE_ID" --org-id "$CH_ORG_ID" --json
npx wrangler hyperdrive get "$HYPERDRIVE_ID"
npx wrangler deployments list --config .deployment/wrangler.json
```

Repeat the runtime privilege checks in README, [CDC verification](../infra/README.md#verify-data-flow),
and [HTTPS checks](hosting.md#7-check-https-and-application-behavior) as needed.
Provider status does not prove sign-in or event delivery.

| Symptom | Check |
| --- | --- |
| Database connection fails only on Workers | Hyperdrive CA/TLS and ClickHouse ingress; local success does not prove hosted connectivity |
| Sign-in fails or loops | Matching Clerk instance/key pair, APP_URL and allowed origin; production domain and DNS-only CNAMEs |
| Analytics says delayed | Postgres click_outbox, Worker cron, ClickHouse INSERT grant and service readiness |
| Tags are still syncing | ClickPipe state, source publication, direct Postgres connection and source/replicated revisions |
| Ownership verified but links unavailable | Hosted hostname configuration and independent DNS/HTTPS check |
| TXT verification fails | Exact record name/value, propagation and resolver errors |

Read the outbox using the runtime login and verified TLS:

```sh
source .deployment/passwords.env
export PGSSLMODE=verify-full
export PGSSLROOTCERT="$PWD/.deployment/postgres-ca.pem"
PGPASSWORD="$PG_APP_PASSWORD" clickhousectl local postgres client \
  --host "$PGHOST" --port "$PGPORT" \
  --query 'SELECT count(*), min(created_at), max(attempts) FROM click_outbox' \
  -- -X -v ON_ERROR_STOP=1 -U link_shortener_app -d "$PGDATABASE"
clickhousectl cloud service query --id "$CH_SERVICE_ID" --org-id "$CH_ORG_ID" \
  --queries-file infra/clickhouse/verify-events.sql
npx wrangler tail --config .deployment/wrangler.json
```

Raw event rows may contain delivery retries; distinct event IDs determine the
reported counts. Reports include bots/previews and use UTC. Raw events expire
eventually after 180 days. Disabling a link returns 410 but retains its data.

## Interrupted setup

Creation and SQL execution are separate commands. A missing response is not proof
of failure. Keep every receipt, even if empty or partial, and inspect the exact
organization/account before another write:

```sh
clickhousectl cloud service list --org-id "$CH_ORG_ID" --json
clickhousectl cloud postgres list --org-id "$CH_ORG_ID" --json
clickhousectl cloud clickpipe list "$CH_SERVICE_ID" --org-id "$CH_ORG_ID" --json
npx wrangler hyperdrive list
npx wrangler cert list
```

Match the intended name, creation time, account, endpoint and configuration.
Inspect a candidate by ID; if the attempted resource exists, record that ID and
continue with it. Recover credentials from the original receipt or your private
backup. Never infer ownership from a common name alone. Only retry creation when
the provider confirms that no resource was created; preserve the failed receipt
under a separate name so the original evidence is retained. Never overwrite the
receipt from a successful create command.

A lost password needs a deliberate credential reset and consumer update, not a
new service. Never delete private state to force recreation. For ambiguous Worker
uploads, inspect the exact Worker and deployment history: secret upload may have
created it before the application deploy failed.

For interrupted SQL, follow [migration recovery](../migrations/README.md#upgrades-and-interrupted-sql).
The manual workflow has no automatic reconciliation, migration ledger or locking;
run one setup/migration session at a time and record completed steps.

### Existing deployments from the old helpers

Keep `cloud-state.json`, `hosting-state.json`, `cloud-secrets.json`, create
receipts, runtime/migration environments and existing private Wrangler config.
Read their resource IDs and credentials into the new private input files rather
than rerunning creation or password generation. Preserve the database's old
`schema_migrations` history. Inspect all provider resources before using their IDs.
The retired JavaScript is not needed to keep the deployed application running.

## Access and credentials

Configure Clerk for your intended users; see [hosting](hosting.md#1-prepare-a-domain-and-authentication).
Public signup requires an operator-owned abuse policy and rate controls beyond
this example. See [Clerk user management](https://clerk.com/docs/guides/users/managing).

Rotate credentials at the provider, update the private files, then update every
consumer. A Postgres runtime password change also requires
`npx wrangler hyperdrive update "$HYPERDRIVE_ID" --origin-password "$PG_APP_PASSWORD"`
with the new value loaded privately. Inspect the resulting TLS/cache settings.
A ClickHouse runtime or Clerk secret change needs Worker secret upload. Changing
a Clerk publishable key also needs a rebuild. Never send migration, CDC or
management credentials to Workers. SQL's `IF NOT EXISTS` clauses do not rotate
existing passwords. Do not regenerate the whole password file to rotate one login.

## Upgrade and recovery

Retain the current source revision, resource inventory, Worker version and database
backup/restore point. Add numbered SQL files instead of changing applied migrations.
Apply only pending SQL with the documented migration login; record each result.

```sh
npm ci
npm test
npm run typecheck
```

Then repeat the [build and Wrangler deployment steps](hosting.md#6-build-upload-secrets-and-deploy)
and signed-in acceptance. A Worker rollback restores code, not schema. Prefer
backward-compatible migrations so the previous Worker can still read the data.

For Postgres recovery, inspect `clickhousectl cloud postgres restore --help` and
restore to a new service at the chosen timestamp. A restored source needs a new
connection/CA/Hyperdrive configuration and a compatible ClickPipe before cutover;
record its new ID without replacing the original receipt. ClickHouse backups and
event retention need separate consideration. Full data-loss recovery and HA/load
drills remain unverified release claims.

## Remove a deployment

Stop traffic and decide whether to drain/export data. Confirm the exact recorded
account, names and IDs with the inspection commands above. Delete only dedicated
resources, in this order. These commands delete the services and their data:

```sh
npx wrangler delete "$WORKER_NAME" --config .deployment/wrangler.json
npx wrangler hyperdrive delete "$HYPERDRIVE_ID"
npx wrangler cert delete --id "$PG_CA_CERT_ID"
clickhousectl cloud clickpipe delete "$CH_SERVICE_ID" "$CLICKPIPE_ID" --org-id "$CH_ORG_ID"
clickhousectl cloud postgres delete "$PG_SERVICE_ID" --org-id "$CH_ORG_ID"
clickhousectl cloud service delete "$CH_SERVICE_ID" --org-id "$CH_ORG_ID" --force
```

Delete the CA only after confirming no other connection uses it. Check the selected
hostnames for leftover DNS/TXT records and edge certificates; remove only items
created for this deployment after checking their use. Keep shared zones, domain
registrations, Clerk instances and unrelated resources.

Confirm removal with successful account-scoped lists. A failed request is not proof
that a resource is absent. Preserve receipts until removal is confirmed. Stopping
your laptop or removing Worker routes does not stop database billing.
