# Optional hosted database connectivity check

The [diagnostic entrypoint](../scripts/workers-connectivity-check.ts) can check the
application's Postgres and ClickHouse drivers from Cloudflare Workers before
Clerk is configured. It is separate from the application and is intended to be
deleted after the check. This optional procedure has not been verified through
a live deployment; record its results independently if you use it.

## Scope and payload

Create private configuration from your recorded deployment.
Use its exact Cloudflare account and Hyperdrive ID. Choose a distinct Worker name
ending in `-runtime-check`, verify that name does not already exist in that account,
and save a private receipt before creation. Do not adopt an existing Worker.

| Item | Diagnostic configuration |
| --- | --- |
| Entrypoint | `../scripts/workers-connectivity-check.ts` from a private `.deployment` config |
| Worker name | Distinct from the application; recorded in the diagnostic receipt |
| Account | Recorded Cloudflare account |
| Hyperdrive | Existing recorded Hyperdrive binding |
| Public endpoint | Temporary `workers.dev` endpoint; no custom-domain routes |
| Scheduled handlers | None; no cron configuration |
| Compatibility | Same compatibility date/flags as the application's recorded config |
| Ordinary vars | None required |

The only secrets uploaded are `DIAGNOSTIC_TOKEN`, generated from 32 random bytes,
and these existing application runtime variables:

- `CLICKHOUSE_URL`
- `CLICKHOUSE_USERNAME`
- `CLICKHOUSE_PASSWORD`
- `CLICKHOUSE_DATABASE`
- `CLICKHOUSE_CDC_DATABASE`

The Worker uses the existing Hyperdrive binding for Postgres. It receives no
Postgres management or migration password, ClickHouse Cloud management key,
Clerk key or Cloudflare management token. Wrangler authenticates the deployment
using the operator's existing session. All generated config, secrets, URLs and
receipts stay under `.deployment` in your checkout.

## Request behavior

The endpoint rejects missing/incorrect bearer tokens and non-GET requests with
HTTP 401 before opening a database connection. An authenticated GET runs exactly
`SELECT 1 AS ok` against Postgres and ClickHouse using the application's runtime
drivers, then closes its request-scoped connections. It returns only:

```json
{
  "stages": [
    { "stage": "postgres", "ok": true },
    { "stage": "clickhouse", "ok": true },
    { "stage": "close", "ok": true }
  ]
}
```

All stages passing produces HTTP 200; database failure produces HTTP 503. It
returns no database rows, hostnames, usernames, passwords, exception messages,
stacks or arbitrary error properties. It writes no application data. The optional
`?port=443` request changes only the ClickHouse HTTPS port; other overrides are
rejected. This lets the operator compare the configured native HTTPS port with
443 without changing the real application's settings.

## Lifecycle (live deployment unverified)

1. Follow the [explicit ingress commands](hosting.md#3-allow-database-connections).
   Inspect the recorded service and organization, review proposed ranges, then use
   `clickhousectl cloud service update --add-ip-allow` for approved missing CIDRs.
   Inspect the result again, preserving unrelated entries. Those shared ranges are a persistent network-access change until
   the service or those ingress rules are removed. Do not widen access further if the test fails.
2. Prepare private config/secrets and record the previously absent diagnostic
   Worker name and account. Upload runtime secrets and deploy that Worker through
   Wrangler. Save command output privately.
3. Read the temporary `workers.dev` URL from Wrangler's deployment output. Check
   that an unauthenticated request returns 401. Make an authenticated GET and save
   only stage results. If ClickHouse fails on its configured HTTPS port, repeat
   with `?port=443` and retain both results.
4. Delete the diagnostic Worker by the exact recorded name/account, including
   after a failed test. Verify its absence through the account's Worker inventory.
   Retain the receipt and private logs. Do not delete the application Worker,
   Hyperdrive, CA, zone, Clerk instance or databases as part of this check.

This proves deployed runtime transport and credentials. It does not prove Clerk
sign-in, link creation, ClickPipes convergence, event ingestion or cron delivery;
those remain part of [fresh-deployment acceptance](v1-readiness.md).
