# ClickHouse ch-1S_1K_IMDB_dataset

Single node ClickHouse instance leveraging 1 ClickHouse Keeper with IMDB dataset 

By default the version of ClickHouse used will be `latest`, and ClickHouse Keeper
will be `latest-alpine`.  You can specify specific versions by setting environment
variables before running `docker compose up`.

This recipe simply automates the [IMDB dataset](https://en.wikipedia.org/wiki/IMDb) loading illustrated [here](https://clickhouse.com/docs/en/integrations/dbt#prepare-clickhouse).

```bash
export CHVER=23.4
export CHKVER=23.4-alpine
docker compose up
```
