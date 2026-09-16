# Deployment and release checklist

Use this checklist for a fresh Shortwave deployment or a release candidate.
Run the walkthrough in [README](../README.md) from your laptop with dedicated
ClickHouse Cloud resources and hostnames you control. Keep
resource IDs, credentials, accounts, screenshots and logs in private receipts.

## Fresh-deployment acceptance

Record the source revision, tool versions and results for each check. A passing
unit test does not establish that a hosted service or integration works.

- [ ] Install the documented tools, clone the repository and run `npm ci`.
- [ ] Run `npm test`, `npm run types:workers`, `npm run typecheck`,
  `npm run build:workers`, and a Wrangler deployment dry run. Report skipped live
  suites separately. Review `npm audit` findings.
- [ ] Review the explicit CLI inputs and commands, then provision ClickHouse Managed Postgres,
  ClickHouse and a links-only ClickPipe. Verify runtime permissions and TLS.
- [ ] Confirm populated metadata snapshot, updates preserving large unchanged
  fields, and delete tombstones converge through ClickPipes.
- [ ] Rehearse an interrupted command: inspect the provider, reuse the recorded
  resource IDs/credentials, and continue without duplicate creation.
- [ ] Build with the private config, inspect the generated target and deploy with Wrangler. Verify public HTTPS, sign-in and
  ownership of the configured short hostname through its TXT challenge.
- [ ] Create, edit, disable and visit links on the application and short hostname.
  Check immediate destination changes, HTTP 410 for disabled links, and HTTP 404
  for missing links or the wrong hostname. HEAD requests must not count visits.
- [ ] Verify a second account cannot read or mutate the first account's data.
- [ ] Exercise tags, folders and UTM templates; download and decode a QR code.
- [ ] Confirm historical UTM values remain unchanged, current tags regroup earlier
  traffic after sync, and retries do not inflate distinct-event counts.
- [ ] Stop local application and event-delivery processes. Generate new hosted
  visits and verify Workers cron delivers them to analytics independently.
- [ ] Redeploy while preserving links, verified domains, resource IDs, runtime
  credentials and analytics.
- [ ] Remove only the dedicated deployment's recorded Worker, Hyperdrive, CA,
  ClickPipe and databases. Check its DNS records and edge certificates; preserve
  shared zones, Clerk instances and unrelated resources.

See [development and checks](development.md) for Cloud integration and browser
fixtures, [Cloud setup](../infra/README.md) for CDC checks, and
[operations](operations.md) for recovery and cleanup.

## Public release review

- [ ] Review the exact files and any Git history being published for credentials,
  personal paths, deployment hostnames, resource IDs and internal working notes.
- [ ] Exclude `.deployment/`, `.private/`, `.secrets/`, `.clickhouse/`, populated
  environment files, CLI logs, browser authentication state and build output.
- [ ] Review every included image for account details, private URLs and tokens.
- [ ] Check local documentation links, provider links, product names and setup
  commands. Keep example values visibly distinct from deployer configuration.
- [ ] Apply the destination repository's license, layout and CI requirements.
  A standalone distribution also needs an explicitly selected license.
- [ ] Record the checks performed for the exact release candidate, including
  failures, skips and unverified environments.

## Scope and limits

Shortwave supports an owner-operated deployment with restricted signup on
Cloudflare Workers. Both databases and ClickPipes run in ClickHouse Cloud.

Development checks have run on Linux arm64 with Node 22.23.2 and clickhousectl
0.4.2. The laptop walkthrough uses standard macOS/Linux tools; full provisioning
from either platform still requires a fresh Cloud rehearsal before release.
Production Clerk sessions must be tested with the operator's own production instance; the
existing automated browser fixtures use development keys.

This example does not provide a public shortening service's abuse-response
process, performance SLA, tested HA/failover plan or complete data-loss recovery
procedure. Review [operations](operations.md) before serving real users.

Vercel, automatic third-party customer-domain onboarding, ClickStack,
pg_clickhouse, teams and additional analytics features are possible extensions,
not implemented capabilities.
