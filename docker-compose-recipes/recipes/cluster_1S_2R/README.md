# ClickHouse cluster cluster_1S_2R

2 ClickHouse instances leveraging 3 dedicated ClickHouse Keepers

1 Shard with replication across clickhouse-01 and clickhouse-02

This Docker compose file deploys a configuration very similar to [this
example in the documentation](https://clickhouse.com/docs/en/architecture/replication).
See the docs for information on terminology, configuration, and testing.
