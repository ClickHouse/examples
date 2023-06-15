# ClickHouse cluster cluster_1S_2R

2 ClickHouse instances leveraging 3 dedicated ClickHouse Keepers

1 Shard with replication across clickhouse-01 and clickhouse-02

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
