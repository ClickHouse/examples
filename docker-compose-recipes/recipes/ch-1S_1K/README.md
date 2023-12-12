# ClickHouse ch-1S_1K

Single node ClickHouse instance leveraging 1 ClickHouse Keeper

1 Shard node on clickhouse and 1 Keeper on clickhouse-keeper

By default the version of ClickHouse used will be `latest`, and ClickHouse Keeper
will be `latest-alpine`.  You can specify specific versions by setting environment
variables before running `docker compose up`.

```bash
export CHVER=23.4
export CHKVER=23.4-alpine
docker compose up
```

This Docker compose file deploys a configuration matching [this
example in the documentation](https://clickhouse.com/docs/en/architecture/replication).
See the docs for information on terminology, configuration, and testing.
