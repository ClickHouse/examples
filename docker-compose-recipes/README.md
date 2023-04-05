# ClickHouse Docker Compose recipes

A list of ClickHouse docker compose recipes

- [ClickHouse and Grafana](./recipes/ch-and-grafana/README.md)
- [ClickHouse and Minio S3](./recipes/ch-and-minio-S3/README.md)
- [Clickhouse and LDAP (OpenLDAP) - WIP](./recipes/ch-and-openldap/README.md)
- [Clickhouse Cluster: 2 CH nodes - 3 ClickHouse Keeper (1 Shard 2 Replicas)](./recipes/cluster_1S_2R/README.md)
- [Clickhouse Cluster: 2 CH nodes - 3 ClickHouse Keeper (2 Shards 1 Replica)](./recipes/cluster_2S_1R/README.md)
- [Clickhouse Cluster: 4 CH nodes - 3 ClickHouse Keeper (2 Shards 2 Replicas)](./recipes/cluster_2S_2R/README.md)
- [Clickhouse Cluster: 2 CH nodes - 3 ClickHouse Keeper (1 Shard 2 Replicas) - CH Proxy LB](./recipes/cluster_1S_2R_ch_proxy/README.md)
- [Clickhouse Cluster: 2 CH nodes - 3 ClickHouse Keeper (2 Shards 1 Replica) - CH Proxy LB](./recipes/cluster_2S_1R_ch_proxy/README.md)
- [Clickhouse Cluster: 4 CH nodes - 3 ClickHouse Keeper (2 Shards 2 Replicas) - CH Proxy LB](./recipes/cluster_2S_2R_ch_proxy/README.md)

These recipes are provided "AS-IS" and intendend strictly and only for local quick and dirty testing.



## How to use

Each recipe runs as a pre-configured docker compose setup.

- clone this repository locally (`cd /opt && git clone https://github.com/ClickHouse/examples`)
- make sure the path _where_ you clone this repo is added to your docker sharing settings
![](./extras/add_path_to_docker_settings.png)
- each recipe has a `script` folder, make sure to run the `create-network.sh` script to create the related docker private bridged network
- `cd` into the desire recipe directory (e.g. `cd recipes/ch-and-grafana`)
- run `docker compose up` to launch the recipe
- ctrl+C will abort executiong
- once done, run `docker compose down` to tear down the environment

## Resources

Make sure enough cpu cores, memory and disk are allocated for docker containers through docker settings.
Some of these recipes do use up to 8 different hosts.

## Example use

To test ClickHouse with S3 functionalities, run [ClickHouse and Minio S3](./recipes/ch-and-minio-S3/README.md) recipe:

```
➜  ch-and-minio-S3 git:(docker-compose-import) ✗ ./scripts/create-docker-network.sh
f520d603cdbef63de8e73b9a3f20f713e634d659670d2f3694e85f4c095bb338
[+] Running 4/2
 ⠿ Network ch-and-minio                       Created                                                                                                                                                                                                                                 0.0s
 ⠿ Container minio                            Created                                                                                                                                                                                                                                 0.0s
 ⠿ Container ch-and-minio-s3-createbuckets-1  Created                                                                                                                                                                                                                                 0.0s
 ⠿ Container clickhouse                       Created                                                                                                                                                                                                                                 0.1s
Attaching to ch-and-minio-s3-createbuckets-1, clickhouse, minio
minio                            | Formatting 1st pool, 1 set(s), 1 drives per set.
minio                            | WARNING: Host local has more than 0 drives of set. A host failure will result in data becoming unavailable.
minio                            | MinIO Object Storage Server
minio                            | Copyright: 2015-2023 MinIO, Inc.
minio                            | License: GNU AGPLv3 <https://www.gnu.org/licenses/agpl-3.0.html>
minio                            | Version: RELEASE.2023-03-24T21-41-23Z (go1.19.7 linux/arm64)
minio                            |
minio                            | Status:         1 Online, 0 Offline.
minio                            | API: http://0.0.0.0:10000
minio                            | Console: http://0.0.0.0:10001
minio                            |
minio                            | Documentation: https://min.io/docs/minio/linux/index.html
minio                            | Warning: The standard parity is set to 0. This can lead to data loss.
ch-and-minio-s3-createbuckets-1  | Added `myminio` successfully.
ch-and-minio-s3-createbuckets-1  | ●  minio:10000
ch-and-minio-s3-createbuckets-1  |    Uptime: 1 second
ch-and-minio-s3-createbuckets-1  |    Version: 2023-03-24T21:41:23Z
ch-and-minio-s3-createbuckets-1  |    Network: 1/1 OK
ch-and-minio-s3-createbuckets-1  |    Drives: 1/1 OK
ch-and-minio-s3-createbuckets-1  |    Pool: 1
ch-and-minio-s3-createbuckets-1  |
ch-and-minio-s3-createbuckets-1  | Pools:
ch-and-minio-s3-createbuckets-1  |    1st, Erasure sets: 1, Drives per erasure set: 1
ch-and-minio-s3-createbuckets-1  |
ch-and-minio-s3-createbuckets-1  | 1 drive online, 0 drives offline
ch-and-minio-s3-createbuckets-1  | Bucket created successfully `myminio/clickhouse`.
ch-and-minio-s3-createbuckets-1  | mc: Please use 'mc anonymous'
ch-and-minio-s3-createbuckets-1 exited with code 0
clickhouse                       | Processing configuration file '/etc/clickhouse-server/config.xml'.
clickhouse                       | Merging configuration file '/etc/clickhouse-server/config.d/config.xml'.
clickhouse                       | Logging debug to /var/log/clickhouse-server/clickhouse-server.log
clickhouse                       | Logging errors to /var/log/clickhouse-server/clickhouse-server.err.log
clickhouse                       | Processing configuration file '/etc/clickhouse-server/config.xml'.
clickhouse                       | Merging configuration file '/etc/clickhouse-server/config.d/config.xml'.
clickhouse                       | Saved preprocessed configuration to '/var/lib/clickhouse/preprocessed_configs/config.xml'.
clickhouse                       | Processing configuration file '/etc/clickhouse-server/users.xml'.
clickhouse                       | Merging configuration file '/etc/clickhouse-server/users.d/users.xml'.
clickhouse                       | Saved preprocessed configuration to '/var/lib/clickhouse/preprocessed_configs/users.xml'.
```

