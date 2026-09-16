# Example scope

Shortwave is a usable link shortener showing the unified data stack in
ClickHouse Cloud. The reader deploys their own
[ClickHouse Managed Postgres](https://clickhouse.com/cloud/postgres), ClickHouse,
and ClickPipe using [clickhousectl](https://clickhouse.com/docs/interfaces/cli),
then deploys the full application to Cloudflare Workers and connects a domain
they control.

The app includes account-owned links, editable destinations, tags, folders,
UTM composition and templates, downloadable QR codes, custom domains, and click
analytics. Its developer lesson is the difference between authoritative
operational state, replicated current metadata, and immutable traffic facts.

The V1 acceptance journey is clone, provision, deploy, attach domain, sign in,
create a link, generate traffic, inspect analytics, edit tags and observe sync,
edit/disable the destination, and remove the deployment's resources.

Read [README](../README.md) for the walkthrough, [architecture](architecture.md)
for data semantics, and the [deployment checklist](v1-readiness.md) for acceptance criteria.
