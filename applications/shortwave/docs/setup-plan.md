# Deployment inputs and order

The step-by-step commands live in [README](../README.md#deploy-your-own-instance)
and the [Workers hosting guide](hosting.md). Database setup uses SQL files passed
directly to `clickhousectl`; hosting uses Wrangler. There is no repository-specific
provisioning runner.

| Input | Source | Used by |
| --- | --- | --- |
| Cloud organization ID and Admin API key pair | [ClickHouse Cloud API keys](https://clickhouse.com/docs/cloud/manage/openapi) | Cloud management and Query API setup |
| Region, Postgres size/version/HA, ClickHouse memory/replicas | Organization's placements and quotas | Database creation |
| Provisioning public egress CIDR | Your laptop's public outbound address | ClickHouse network access |
| Cloudflare account and active zone | Operator's Cloudflare account | Worker, Hyperdrive, certificates and hostnames |
| Application and short-link hostnames | Domain controlled by the operator | Clerk, Worker routes and application domains |
| Matching Clerk key pair | Operator's Clerk instance | Browser authentication and session validation |
| Postgres CA registration ID | Wrangler CA upload | Hyperdrive verified origin TLS |

## Sequence

1. Install clickhousectl on your laptop, clone the repo, and run `npm ci` to
   install app dependencies and Wrangler. Sign in to ClickHouse Cloud and Cloudflare.
2. Save private inputs and review the actual create commands: placement, sizes,
   ingress and costs are explicit in README.
3. Create ClickHouse and ClickHouse Managed Postgres with `clickhousectl`. Keep create
   receipts, record IDs, inspect readiness and download the CA.
4. Run the Postgres role SQL, numbered schema files, grants and publication SQL.
   Use the administrator only where needed; the migration login owns app tables.
5. Run ClickHouse database/event/user/grant SQL through the Cloud Query API.
6. Create the links ClickPipe using the checked-in mapping. Inspect its destination
   and grant runtime SELECT. Save runtime credentials separately.
7. Configure Clerk, networking and Hyperdrive with the documented commands. Fill
   the private Wrangler config using the recorded account, IDs and hostnames.
8. Build with that config and the Clerk publishable key, inspect the generated
   deployment target, upload runtime secrets and deploy with Wrangler.
9. Verify the short domain's TXT challenge and complete [acceptance](v1-readiness.md).
10. Keep the receipts for [operations and cleanup](operations.md).

## Private files

Use ignored `.deployment/` files for `resources.env` (inputs, endpoints and IDs),
`passwords.env` (separate database passwords),
`clerk.env`, `runtime.env`, the CA, rendered SQL, Wrangler config and CLI receipts.
Never publish these or credential-bearing logs. Keep `.clickhouse/` private too:
the CLI may store management and service Query API credentials there.

Record completed commands. Inspect ambiguous results before retrying and reuse
the exact resource IDs. The CLI workflow does not automatically reconcile outcomes
or record migration hashes. See [migration records](../migrations/README.md).
Existing deployments retain their earlier private receipts and credentials.
Use a separate checkout/private directory for a separate deployment.

## Domain scope

The operator configures hostnames in their Cloudflare account. For example,
`app.mydomain.com` hosts the app and `mydomain.com/r/<slug>` hosts short links.
Use `go.mydomain.com` if the apex is occupied. No infrastructure is created per link.
Automatic onboarding of unrelated customers' domains remains a future extension.
