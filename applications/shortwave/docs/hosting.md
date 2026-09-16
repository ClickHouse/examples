# Deploy the application to Cloudflare Workers

Run these commands from the project root in your laptop terminal (Bash or zsh).
Complete the [database setup in README](../README.md#deploy-your-own-instance)
first. Keep `.deployment/resources.env`, `passwords.env`, `runtime.env`, service
receipts, and `postgres-ca.pem` private. Use the lockfile's Wrangler version.

## 1. Prepare a domain and authentication

Choose an application hostname and a short-link hostname in an active Cloudflare
zone in your account. Use a short-link subdomain if your apex already hosts a
website. Resolve conflicting DNS records before attaching the hostnames.
[Workers Custom Domains](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/)
configures routing DNS and HTTPS certificates.

Bring your own Clerk production application and restrict signup to your intended
users. Complete its domain/DNS setup; Clerk CNAME records should be **DNS only**
in Cloudflare. See [Clerk production deployment](https://clerk.com/docs/guides/development/deployment/production).

Create `.deployment/clerk.env` in an editor, using a matching pair from that instance:

```dotenv
VITE_CLERK_PUBLISHABLE_KEY=pk_live_replace_me
CLERK_SECRET_KEY=sk_live_replace_me
```

For local development or disposable evaluation, use a separate Clerk development
instance with matching `pk_test_` / `sk_test_` keys. Production session behavior
needs its own acceptance check. Never mix keys from different instances.

Add these inputs to `.deployment/resources.env`:

```dotenv
CLOUDFLARE_ACCOUNT_ID=YOUR_CLOUDFLARE_ACCOUNT_ID
WORKER_NAME=shortwave-example
APP_HOSTNAME=app.mydomain.com
SHORT_HOSTNAME=mydomain.com
```

```sh
umask 077
source .deployment/resources.env
source .deployment/passwords.env
source .deployment/clerk.env
export CLOUDFLARE_ACCOUNT_ID
npx wrangler whoami
```

README already signed you in to Wrangler. `export CLOUDFLARE_ACCOUNT_ID` tells
Wrangler which of your accounts to use. Verify the selected account before any
write. It must match `account_id` in the private Wrangler config below. Reuse a valid Wrangler
session; `whoami` checks it. For noninteractive use, store a scoped
`CLOUDFLARE_API_TOKEN` as a secret environment variable in your CI system.
[Wrangler authentication](https://developers.cloudflare.com/workers/wrangler/commands/general/)
uses either the session or that token.

A scoped token needs Workers Scripts: Edit, Hyperdrive: Edit, and SSL and
Certificates: Edit in the selected account, plus Zone: Read and Workers Routes:
Edit for the selected zones. DNS: Edit is needed only if you automate DNS record
changes. Check the current [permission labels](https://developers.cloudflare.com/fundamentals/api/reference/permissions/).

## 2. Upload the Postgres CA

Inspect existing certificates before creating one, then record the upload output:

```sh
npx wrangler cert list
npx wrangler cert upload certificate-authority \
  --ca-cert .deployment/postgres-ca.pem --name "$WORKER_NAME-postgres-ca" \
  > .deployment/ca-upload.txt
```

Save the returned ID as `PG_CA_CERT_ID` in `.deployment/resources.env`, then
source the file again. On an interrupted upload, inspect the account's certificate
list and match the certificate before retrying. See
[Wrangler certificates](https://developers.cloudflare.com/workers/wrangler/commands/certificates/)
and [Hyperdrive TLS](https://developers.cloudflare.com/hyperdrive/configuration/tls-ssl-certificates-for-hyperdrive/).

## 3. Allow database connections

Hyperdrive must reach the Postgres origin. If that endpoint has a firewall,
configure it using [Hyperdrive networking](https://developers.cloudflare.com/hyperdrive/configuration/firewall-and-networking-configuration/).

For ClickHouse, use the CLI login from README and inspect current access rules
alongside Cloudflare's published ranges:

```sh
clickhousectl cloud service get "$CH_SERVICE_ID" --org-id "$CH_ORG_ID" --json \
  > .deployment/clickhouse-current.json
curl --fail --silent --show-error https://api.cloudflare.com/client/v4/ips \
  > .deployment/cloudflare-ips.json
jq '.ipAccessList' .deployment/clickhouse-current.json
jq -er '.result.ipv4_cidrs[]' .deployment/cloudflare-ips.json
```

Review the proposed additions. To allow a range you have approved, repeat this
command for each missing CIDR, replacing the placeholder with the actual range:

```sh
clickhousectl cloud service update "$CH_SERVICE_ID" --org-id "$CH_ORG_ID" \
  --add-ip-allow 'APPROVED_CLOUDFLARE_CIDR' --json
```

`--add-ip-allow` preserves unrelated entries. Record added CIDRs privately and
inspect the service again after updating. Do not replace the access list or add
`0.0.0.0/0` as a connectivity workaround. These are shared ranges, so restricted
database credentials remain required. Published proxy ranges alone do not prove
egress for every Workers transport; verify the app's actual HTTPS ClickHouse
connection with hosted analytics and event delivery.

## 4. Create Hyperdrive

Inspect the account before creation, then create the connection using the
restricted Postgres runtime user:

```sh
npx wrangler hyperdrive list
npx wrangler hyperdrive create "$WORKER_NAME-postgres" \
  --origin-host "$PGHOST" --origin-port "$PGPORT" --database "$PGDATABASE" \
  --origin-scheme postgres --origin-user link_shortener_app \
  --origin-password "$PG_APP_PASSWORD" \
  --ca-certificate-id "$PG_CA_CERT_ID" --sslmode verify-full \
  --caching-disabled --origin-connection-limit 20 \
  > .deployment/hyperdrive-create.txt
```

Keep shell tracing disabled and command output private when supplying passwords.

Save the returned ID as `HYPERDRIVE_ID` in `.deployment/resources.env` and reload
it. On retries, inspect the recorded ID instead of creating a second connection:

```sh
npx wrangler hyperdrive get "$HYPERDRIVE_ID"
```

Confirm the origin host, port, database, and user match the recorded Postgres
runtime connection; `caching.disabled` must be `true`, the CA ID must match, and
`sslmode` must be `verify-full`. Query caching must stay disabled so redirects and
authorization see current data. See [Wrangler Hyperdrive commands](https://developers.cloudflare.com/hyperdrive/reference/wrangler-commands/).

## 5. Fill the private Wrangler configuration

Create `.deployment/wrangler.json` with the following content. Replace the account,
Worker name, hostnames and Hyperdrive ID with your recorded inputs. Keep paths
relative to `.deployment`; keep the generic development config in the project
root. Add another custom-domain route and comma-separated `PUBLIC_CUSTOM_DOMAINS`
entry if you need another short hostname.

```json
{
  "$schema": "../node_modules/wrangler/config-schema.json",
  "name": "YOUR_WORKER_NAME",
  "account_id": "YOUR_CLOUDFLARE_ACCOUNT_ID",
  "main": "../src/worker.ts",
  "compatibility_date": "2026-09-06",
  "compatibility_flags": ["nodejs_compat", "global_fetch_strictly_public"],
  "workers_dev": false,
  "vars": {
    "APP_URL": "https://app.mydomain.com",
    "PUBLIC_CUSTOM_DOMAINS": "mydomain.com"
  },
  "hyperdrive": [{ "binding": "HYPERDRIVE", "id": "YOUR_HYPERDRIVE_ID" }],
  "routes": [
    { "pattern": "app.mydomain.com", "custom_domain": true },
    { "pattern": "mydomain.com", "custom_domain": true }
  ],
  "secrets": {
    "required": [
      "CLERK_SECRET_KEY", "CLICKHOUSE_URL", "CLICKHOUSE_USERNAME",
      "CLICKHOUSE_PASSWORD", "CLICKHOUSE_DATABASE", "CLICKHOUSE_CDC_DATABASE"
    ]
  },
  "observability": { "enabled": true, "head_sampling_rate": 1 },
  "triggers": { "crons": ["* * * * *"] }
}
```

Before the first upload, check in Cloudflare that the Worker name is unused and
that none of these hostnames belongs to another Worker. For an existing deployment,
compare the private config with its recorded account, names, IDs and hostnames.
Wrangler can overwrite an existing Worker, so do not adopt a name merely because
it matches. The scheduled event sender runs every minute.

## 6. Build, upload secrets, and deploy

Build using the private config and your Clerk publishable key:

```sh
CLOUDFLARE_VITE_WRANGLER_CONFIG_PATH="$PWD/.deployment/wrangler.json" \
  VITE_CLERK_PUBLISHABLE_KEY="$VITE_CLERK_PUBLISHABLE_KEY" npm run build:workers
BUILD_CONFIG="$PWD/.wrangler/deploy/$(jq -er '.configPath' .wrangler/deploy/config.json)"
jq '{name, account_id, hyperdrive, vars, routes, triggers}' "$BUILD_CONFIG"
```

The [Cloudflare Vite plugin](https://developers.cloudflare.com/workers/vite-plugin/reference/api/)
generates the deployment config. Verify that the output contains your recorded
Worker, account, Hyperdrive binding, hostnames and scheduler before uploading.
Deploy that generated config so the Worker includes the built application/assets.
Do not deploy the generic development template.

Create a secrets file containing only the values the Worker needs. Wrangler
accepts this standard environment-file format directly:

```sh
source .deployment/runtime.env
source .deployment/clerk.env
cat > .deployment/workers-secrets.env <<SECRETS
CLERK_SECRET_KEY=$CLERK_SECRET_KEY
CLICKHOUSE_URL=$CLICKHOUSE_URL
CLICKHOUSE_USERNAME=$CLICKHOUSE_USERNAME
CLICKHOUSE_PASSWORD=$CLICKHOUSE_PASSWORD
CLICKHOUSE_DATABASE=$CLICKHOUSE_DATABASE
CLICKHOUSE_CDC_DATABASE=$CLICKHOUSE_CDC_DATABASE
SECRETS
npx wrangler deploy --dry-run --config "$BUILD_CONFIG"
npx wrangler secret bulk .deployment/workers-secrets.env --config "$BUILD_CONFIG"
npx wrangler deploy --config "$BUILD_CONFIG"
```

Secret upload can create an empty Worker before deployment. If interrupted, inspect
that exact Worker before retrying; retain its receipt. Hyperdrive already holds
the Postgres runtime connection. Never upload the administrator, migration, CDC,
Cloud API, or Cloudflare credentials as Worker secrets.

## 7. Check HTTPS and application behavior

```sh
curl --fail --silent --show-error -o /dev/null -w '%{http_code}\n' \
  "https://$APP_HOSTNAME/sign-in"
curl --silent --show-error --dump-header - -o /dev/null "https://$SHORT_HOSTNAME/"
npx wrangler deployments list --config .deployment/wrangler.json
```

Expect HTTP 200 for sign-in and HTTP 302 from the short hostname to the configured
application origin. These checks prove DNS/TLS/routing only. Sign in, add your
short hostname in **Domains**, publish the displayed TXT challenge and verify it.
Create and visit a link on that hostname. Complete the
[fresh-deployment checklist](v1-readiness.md), including data flow after you close
the deployment terminal.

For updates, repeat the build, config inspection, secret upload and deploy steps.
Apply new SQL migrations first when required. For diagnostics:

```sh
npx wrangler hyperdrive get "$HYPERDRIVE_ID"
npx wrangler tail --config .deployment/wrangler.json
```

See [operations](operations.md) for interrupted commands, rotation, rollback and
explicit resource deletion commands.
