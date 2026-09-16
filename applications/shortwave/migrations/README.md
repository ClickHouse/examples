# Schema migrations

Apply these SQL files with the explicit `clickhousectl` commands in the
[project README](../README.md#3-create-postgres-roles-and-apply-sql). Read each file
before running it. Postgres application tables belong to
`link_shortener_migration`; use that login for migrations.

| Order | File | Change |
| --- | --- | --- |
| 1 | [postgres/001_initial.sql](postgres/001_initial.sql) | Accounts, links, templates, QR styles and durable event outbox |
| 2 | [postgres/002_saved_tags.sql](postgres/002_saved_tags.sql) | Saved account tags and backfill |
| 3 | [postgres/003_folders.sql](postgres/003_folders.sql) | Folders and link membership |
| 4 | [postgres/004_custom_domains.sql](postgres/004_custom_domains.sql) | Domain ownership claims |
| 5 | [postgres/005_domain_links.sql](postgres/005_domain_links.sql) | Domain-scoped links and slug uniqueness |
| 6 | [../infra/postgres/002_grants.sql](../infra/postgres/002_grants.sql) | Runtime/CDC grants and replica identity after table creation |

ClickHouse uses [clickhouse/001_events.sql](clickhouse/001_events.sql), applied
with `--database link_shortener`. The metadata fixture
[clickhouse/002_local_metadata.sql](clickhouse/002_local_metadata.sql) is **local
only**; never apply it to ClickHouse Cloud. ClickPipes owns `default.cdc_links`.

## Upgrades and interrupted SQL

Add a numbered file for each new schema change; preserve already-applied files.
Keep a private record of the source revision, successful filenames and checksums:

```sh
openssl dgst -sha256 migrations/postgres/*.sql migrations/clickhouse/001_events.sql \
  > .deployment/migration-checksums.txt
```

This is an operator record, not an automatic migration ledger. Save a separate
copy per release, mark each completed command, and apply only pending migrations
on upgrades. Stop on any error before running the next file. Postgres files wrap
their changes in a transaction; an interrupted connection rolls back an uncommitted
transaction. A lost response may follow a successful commit, so inspect the
schema before retrying. Do not run concurrent migrations.

For deployments previously created by the JavaScript bootstrap, retain the
existing private receipts and `schema_migrations` table. Use its filenames and
hashes to establish what is already applied; do not regenerate passwords or
recreate services. The direct CLI workflow does not update that old ledger.
Record subsequent migrations separately. Existing roles and Cloud resources
remain usable without the retired setup code.

The five current Postgres files can be reapplied when recovering their outcome,
but some include data backfills. Review their effects rather than treating every
future migration as automatically safe to rerun. ClickHouse DDL has no enclosing
transaction; inspect the destination before retrying a timed-out statement.
