# ClickHouse cluster cluster_2S_1R

2 ClickHouse instances leveraging 3 dedicated ClickHouse Keepers and CH Proxy load balancer

2 Shards with no replication configured


This Docker compose file deploys a configuration similar to [this
example in the documentation](https://clickhouse.com/docs/en/architecture/horizontal-scaling) with the main difference being that 3 independent ClickHouse keeper instances are used in this recipe (instead of just one as in the docs).
See the docs for information on terminology, configuration, and testing.

See the [Chproxy docs](https://www.chproxy.org/) for information on the proxy. See the [license](https://github.com/ContentSquare/chproxy/blob/master/LICENSE) in the GitHub repo.
