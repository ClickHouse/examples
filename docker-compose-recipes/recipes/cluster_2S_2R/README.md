# ClickHouse cluster cluster_2S_2R

4 ClickHouse instances leveraging 3 dedicated ClickHouse Keepers

2 Shards with replication:
- across clickhouse-01 and clickhouse-03 for shard 01
- across clickhouse-02 and clickhouse-04 for shard 02

By default the version of ClickHouse used will be `latest`, and ClickHouse Keeper
will be `latest-alpine`.  You can specify specific versions by setting environment
variables before running `docker compose up`.

```bash
export CHVER=23.4
export CHKVER=23.4-alpine
docker compose up
```

This Docker compose file deploys a configuration very similar to [these two
examples in the documentation](https://clickhouse.com/docs/en/architecture/introduction).
See the docs for information on terminology, configuration, and testing.
