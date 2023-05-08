# ClickHouse cluster cluster_2S_2R

4 ClickHouse instances leveraging 3 dedicated ClickHouse Keepers

2 Shards with replication:
- across clickhouse-01 and clickhouse-03 for shard 01
- across clickhouse-02 and clickhouse-04 for shard 02

This Docker compose file deploys a configuration very similar to [these two
examples in the documentation](https://clickhouse.com/docs/en/architecture/introduction).
See the docs for information on terminology, configuration, and testing.
