# Architecture

Shortwave separates operational state, metadata replication, and traffic facts.
All data services run in ClickHouse Cloud; the complete TanStack Start application
runs on Cloudflare Workers. Clerk supplies authentication and Click UI supplies
the interface components.

## Operational data

[ClickHouse Managed Postgres](https://clickhouse.com/cloud/postgres) owns accounts,
links, custom domains, tags, folders, UTM templates, QR styles, and the click
outbox. Server functions obtain the identity
from Clerk's verified session and scope each operation to its account. Composite
foreign keys preserve account ownership for folders and custom domains.

A redirect resolves the exact hostname and slug in Postgres. Slugs and domain
assignment are immutable; destinations and enabled status can change. Successful
GET redirects commit an event to the outbox before returning HTTP 302 with
caching disabled. HEAD resolves without recording traffic. Missing links return
404 and disabled links return 410. A Postgres or outbox-commit failure fails the
redirect; ClickHouse availability is not on the redirect's critical path.

Workers connects through Hyperdrive with origin certificate verification and
query caching disabled, so operational changes are read immediately. Node
development connects directly using the service CA. Runtime connections are
scoped to a Worker invocation and closed after response streaming completes.

## Traffic facts

The scheduled Worker runs every minute and drains at most five batches of 500
outbox events. Delivery uses row locks and SKIP LOCKED; transient insert failures
are retried with backoff. ClickHouse inserts use async_insert=1 and
wait_for_async_insert=1. An acknowledgement or transaction-commit failure can
cause another delivery of the same immutable event ID.

Reports use uniqExact(event_id), not raw row counts, so at-least-once delivery
does not inflate the displayed totals. click_events is a MergeTree table ordered
by account_id, occurred_at, link_id, event_id, partitioned monthly, with eventual
180-day TTL expiry. UTC reports offer up to 90 days and a preceding comparison.
The current day is partial. Counts include bots and previews and do not measure
unique people, physical QR scans, or destination-page loads. No IP fingerprint
is stored; geography is not inferred without a trusted signal.

UTM values are captured at the time of the redirect. Updating a saved UTM
template does not rewrite existing links or historical events. A QR code encodes
the short URL, so changing the destination preserves printed QR codes.

## Metadata sync

ClickPipes replicates only public.links, including the tags array, into
cdc_links. Saved tag vocabulary, folders, domain ownership, and Clerk data remain
outside the publication. ClickPipes creates and owns the destination table;
never apply migrations/clickhouse/002_local_metadata.sql to Cloud.

Current-state queries use a ReplacingMergeTree destination ordered by stable id,
FINAL, and _peerdb_is_deleted = 0. The app compares source and replicated link
revisions to show a syncing state. Current tags regroup historical traffic after
replication catches up; historical UTMs stay unchanged. These semantics follow
[ClickPipes deduplication guidance](https://clickhouse.com/docs/integrations/clickpipes/postgres/deduplication).

The tested CLI baseline is
[clickhousectl](https://clickhouse.com/docs/interfaces/cli) 0.4.2. Its Postgres ClickPipe destination
is default; event data is in link_shortener. CLICKHOUSE_CDC_DATABASE qualifies
metadata separately. Explicit table-mapping JSON selects ReplacingMergeTree and
id sorting instead of relying on CLI defaults. Other CLI versions must be checked
against their help and verified before changing this contract.

## Domains and previews

TXT verification proves that an application account controls an exact hostname.
Hosting configuration separately permits that hostname to serve links.
[Custom domains](custom-domains.md) explains the operator setup and lifecycle.

Authenticated destination previews permit bounded public HTTP(S) resources and
repeat validation for redirects. Private/reserved addresses, mixed public/private
DNS answers, credentials, unsupported ports, oversized resources, and SVG images
are rejected. Node pins connections to a validated address; Workers uses public
egress fetch with global_fetch_strictly_public and platform TLS verification.
The browser receives bounded raster data URLs instead of fetching preview images
directly. Preview caches and concurrency controls are ephemeral per process.

## Limits and extensions

The app limits each account to 100 new links per rolling day and 100 folders.
These controls do not replace signup policy or abuse operations. The reference
instance is intended for an operator's own users. See [operations](operations.md)
for access, delivery failures, retention, recovery, and cleanup.

Cloudflare for SaaS customer-domain onboarding, Vercel, teams, pg_clickhouse,
ClickStack, aggregate materialized views, and load/HA benchmarking are extensions.
None is required for the V1 data flow. Do not add aggregate views without proving
that retries and metadata changes preserve analytical correctness.
