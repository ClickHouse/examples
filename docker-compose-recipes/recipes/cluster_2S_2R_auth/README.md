# ClickHouse cluster cluster_2S_2R_auth with inter node authentication

4 ClickHouse instances leveraging 3 dedicated ClickHouse Keepers

2 Shards with replication:
- across clickhouse-01 and clickhouse-03 for shard 01
- across clickhouse-02 and clickhouse-04 for shard 02

This recipe implements also:

- cluster inter-nodes authentication for distributed queries (`<secret>`)
- cluster interserver http channel for low-level replication (`<interserver_http_credentials>`)
- keeper authentication through auth digest scheme (`<identity>`)

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
