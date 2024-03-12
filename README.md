# ClickHouse Examples
## ClickHouse Blog data

A collection of data required to back our own ClickHouse official [Blogs](clickhouse.com/blog), including:
- [DDL](./ethereum/schemas/) statements;
- SQL [queries](./ethereum/queries/);
- a collection of agents (Vector, FluentBit, etc) [configurations](./observability/README.md) to analyze Kubernetes logs in ClickHouse;
- more;

## ClickHouse docker compose recipes

A [list](./docker-compose-recipes/README.md) of ClickHouse recipes using docker compose:

- ClickHouse single node with Keeper
- ClickHouse single node with Keeper and IMDB dataset
- ClickHouse and Dagster
- ClickHouse and Grafana
- ClickHouse and MSSQL Server 2022
- ClickHouse and MinIO S3
- ClickHouse and LDAP (OpenLDAP)
- ClickHouse and Postgres
- ClickHouse and Vector syslog and apache demo data
- ClickHouse Cluster: 2 CH nodes - 3 ClickHouse Keeper (1 Shard 2 Replicas)
- ClickHouse Cluster: 2 CH nodes - 3 ClickHouse Keeper (2 Shards 1 Replica)
- ClickHouse Cluster: 4 CH nodes - 3 ClickHouse Keeper (2 Shards 2 Replicas)
- ClickHouse Cluster: 4 CH nodes - 3 ClickHouse Keeper (2 Shards 2 Replicas) with inter-nodes and keeper digest authentication
- ClickHouse Cluster: 2 CH nodes - 3 ClickHouse Keeper (1 Shard 2 Replicas) - CH Proxy LB
- ClickHouse Cluster: 2 CH nodes - 3 ClickHouse Keeper (2 Shards 1 Replica) - CH Proxy LB
- ClickHouse Cluster: 4 CH nodes - 3 ClickHouse Keeper (2 Shards 2 Replicas) - CH Proxy LB

These recipes are meant to provide a quick n dirty way to get started and try out specific type of ClickHouse integration or clustered environment locally.

Last but not least, feel free to contribute by submitting a PR!
