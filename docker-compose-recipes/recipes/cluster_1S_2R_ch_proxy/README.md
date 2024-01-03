# ClickHouse cluster cluster_1S_2R

2 ClickHouse instances leveraging 3 dedicated ClickHouse Keepers and CH Proxy load balancer

1 Shard with replication across clickhouse-01 and clickhouse-02

By default the version of ClickHouse used will be `latest`, and ClickHouse Keeper
will be `latest-alpine`.  You can specify specific versions by setting environment
variables before running `docker compose up`.

```bash
export CHVER=23.4
export CHKVER=23.4-alpine
docker compose up
```

This Docker compose file deploys a configuration very similar to [this
example in the documentation](https://clickhouse.com/docs/en/architecture/replication), the main difference is that this adds Chproxy.
See the docs for information on terminology, configuration, and testing.

See the [Chproxy docs](https://www.chproxy.org/) for information on the proxy. See the [license](https://github.com/ContentSquare/chproxy/blob/master/LICENSE) in the GitHub repo.
