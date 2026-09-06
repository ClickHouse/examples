# ClickHouse Docker Compose recipes

Small local examples for learning ClickHouse topologies and integrations. These
are development environments with public example credentials and no production
security, backup or availability guarantees. Run one recipe at a time: several
use the same host ports. Refreshed core recipes bind host ports to loopback;
check older integrations before starting them on a shared machine.

- [ClickHouse single node with Keeper](./recipes/ch-1S_1K/README.md)
- [ClickHouse single node with Keeper and IMDB dataset](./recipes/ch-1S_1K_IMDB_dataset/README.md)
- [ClickHouse and Dagster](./recipes/ch-and-dagster/README.md)
- [ClickHouse and Grafana](./recipes/ch-and-grafana/README.md)
- [ClickHouse and MSSQL Server 2022](./recipes/ch-and-mssql/README.md)
- [ClickHouse and S3-compatible SeaweedFS](./recipes/ch-and-seaweedfs/README.md)
- [ClickHouse and S3-compatible RustFS (beta)](./recipes/ch-and-rustfs/README.md)
- [ClickHouse and Postgres](./recipes/ch-and-postgres/README.md)
- [ClickHouse Cluster: 2 CH nodes - 3 ClickHouse Keeper (1 Shard 2 Replicas) - CH Proxy LB](./recipes/cluster_1S_2R_ch_proxy/README.md)
- [ClickHouse Cluster: 2 CH nodes - 3 ClickHouse Keeper (1 Shard 2 Replicas)](./recipes/cluster_1S_2R/README.md)
- [ClickHouse Cluster: 2 CH nodes - 3 ClickHouse Keeper (2 Shards 1 Replica) - CH Proxy LB](./recipes/cluster_2S_1R_ch_proxy/README.md)
- [ClickHouse Cluster: 2 CH nodes - 3 ClickHouse Keeper (2 Shards 1 Replica)](./recipes/cluster_2S_1R/README.md)
- [ClickHouse Cluster: 4 CH nodes - 3 ClickHouse Keeper (2 Shards 2 Replicas) - CH Proxy LB](./recipes/cluster_2S_2R_ch_proxy/README.md)
- [ClickHouse Cluster: 4 CH nodes - 3 ClickHouse Keeper (2 Shards 2 Replicas) with inter-nodes and keeper digest authentication](./recipes/cluster_2S_2R_auth/README.md)
- [ClickHouse Cluster: 4 CH nodes - 3 ClickHouse Keeper (2 Shards 2 Replicas)](./recipes/cluster_2S_2R/README.md)
- [ClickHouse and LDAP (OpenLDAP)](./recipes/ch-and-openldap/README.md)
- [ClickHouse and Vector syslog and apache demo data](./recipes/ch-and-vector/README.md)

SeaweedFS and RustFS keep the object-storage lesson small. Ceph was evaluated but
excluded because its local operational footprint is disproportionate to this quick start.

## Start, verify and reset

Install Docker with Compose v2 (`docker compose version`). No host application
packages are needed. Allow Docker access to your checkout if your desktop runtime
requires file sharing. Budget at least 2 CPUs and 4 GiB RAM for a small recipe;
clusters need more, as described in their READMEs.

From the repository root, for example:

```sh
cd docker-compose-recipes/recipes/ch-1S_1K
docker compose up -d
```

Refreshed recipes include bounded verification commands, fixture assertions and
the actual ClickHouse version from their manual run. Follow the selected README;
older integrations are being refreshed independently.
To inspect a failure, use `docker compose ps` and `docker compose logs --tail=100`.
To stop and reset a recipe:

```sh
docker compose down -v --remove-orphans
```

`down -v` deletes that project's volumes and their data. It does not delete any
host bind-mounted data; follow the recipe's instructions for those paths.

ClickHouse defaults to `CHVER=latest`; Keeper defaults to `CHKVER=latest-alpine`.
To try a particular release, set `CHVER` and `CHKVER` before starting the recipe.
Manual verification records a date, platform and actual version; floating defaults
can change after that date. Third-party images may use a tested stable tag.

Configuration lives in each recipe's `fs/volumes/` directory. Existing cluster
paths are used by [ClickHouse's replication documentation](https://clickhouse.com/docs/architecture/replication).
The XML element is named `zookeeper` even when its servers are ClickHouse Keeper.
Coordinate changes to those documented cluster configurations with documentation
owners before merging.

## Lightweight validation

Run from the repository root with existing Python 3 (standard library only) and
Docker Compose v2; no package installation or running containers are needed:

```sh
python3 docker-compose-recipes/scripts/validate.py
```

This checks local index links, a README for every recipe, Compose configuration,
and XML syntax. It does not start services or prove integration compatibility.
When changing a recipe, run its documented happy path once from empty volumes and
include commands, results, date, platform and versions in the PR. There is no
scheduled test suite or version matrix.

## ClickHouse Cloud

[ClickHouse Cloud](https://clickhouse.com/cloud) manages ClickHouse infrastructure.
[ClickPipes](https://clickhouse.com/cloud/clickpipes) provides managed ingestion for
supported sources. Each refreshed recipe explains the applicable Cloud path;
Keeper and proxy topology internals are self-managed lessons.
