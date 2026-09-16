# Decisions

| Decision | Reason |
| --- | --- |
| ClickHouse Cloud only | ClickHouse Managed Postgres owns operational data, ClickHouse serves analytics, and ClickPipes syncs metadata in one data platform |
| [clickhousectl](https://clickhouse.com/docs/interfaces/cli) for Cloud provisioning | One inspectable CLI manages Cloud service lifecycle and CDC; SQL execution dependencies are documented explicitly |
| Explicit CLI steps and SQL files | Readers deploy from their laptops using clickhousectl and Wrangler; SQL files show database setup. The maintainer VM is a development choice |
| Cloudflare Workers for V1 | One deployment runs the TanStack frontend, server functions, redirects, and scheduled delivery |
| Clerk for identity | Server-verified sessions map to account-scoped application data |
| TanStack Start, React, Click UI | A complete application interface with server functions and the ClickHouse design system |
| Hyperdrive, verified TLS, no query cache | Pool connections while preserving current operational reads |
| Durable Postgres outbox | Successful redirects record events before acknowledgement; cron handles temporary ClickHouse failures |
| Distinct event IDs in reports | At-least-once retries must not inflate counts |
| ClickPipes-managed links metadata | Current tag filters demonstrate operational edits propagating into analytics |
| 180-day eventual raw-event TTL | Supports 90-day reports with a preceding-period comparison |
| Operator-owned domains | A complete self-hosting path without building a multi-customer hostname provisioning service |
| /r/:slug, HTTP 302, no cache | Namespaces redirects and allows immediate destination changes |
| Immutable slug/domain assignment | Keeps printed short URLs and QR codes stable |
| Plain UI copy | Page titles and helper text describe tasks or actionable states |

[Architecture](architecture.md) explains the data contracts and failure behavior.
[Deployment](setup-plan.md) defines setup inputs and commands.
[Deployment checks](v1-readiness.md) define acceptance criteria and verification limits.

Vercel, automatic third-party domain onboarding, teams, ClickStack, pg_clickhouse,
materialized aggregates, and performance/HA benchmarking remain extensions.
