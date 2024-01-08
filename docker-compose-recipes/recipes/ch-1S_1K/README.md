# ClickHouse ch-1S_1K

Single node ClickHouse instance leveraging 1 ClickHouse Keeper

By default the version of ClickHouse used will be `latest`, and ClickHouse Keeper
will be `latest-alpine`.  You can specify specific versions by setting environment
variables before running `docker compose up`.

```bash
export CHVER=23.4
export CHKVER=23.4-alpine
docker compose up
```
