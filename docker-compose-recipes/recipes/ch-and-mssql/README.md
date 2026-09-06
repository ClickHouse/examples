# ClickHouse + Microsoft SQL Server through ODBC

Query a five-row SQL Server table from ClickHouse using the `odbc()` table function and the `ODBC` table engine. Two services run locally: SQL Server Developer Edition and a ClickHouse image extended with unixODBC, Microsoft ODBC Driver 18, and the separate ClickHouse ODBC bridge. Data stays in SQL Server and is read when queried; this is federation, not a CDC pipeline.

## Requirements and architecture

Use Docker with Compose v2 and a POSIX shell. Allow about 4 CPUs, 8 GiB RAM and 8 GiB free disk in Docker for the two databases, build layers, and images. All packages and database clients run **inside containers**; no host pip/npm, ODBC, or database-client installation is needed.

**Microsoft supports SQL Server Linux containers on native Intel/AMD x86-64 Linux hosts only.** The Compose service explicitly requests `linux/amd64`. Running it on Apple Silicon or another arm64 host requires experimental emulation, which Microsoft does not test or support. A successful emulated run does not establish native arm64 support; use a native amd64 Linux Docker host if your emulator cannot run it.

The ClickHouse image, ODBC bridge, and Microsoft ODBC Driver 18 packages have amd64 and arm64 builds; driver registration is supplied by the Microsoft package without a hardcoded library path. `CHVER` defaults to `latest` and is forwarded to the Docker build. Other versions must use an Ubuntu-based ClickHouse image with its signed package repository; an Alpine image cannot run this apt-based Dockerfile. The bridge is pinned independently to `25.1.5.31`; upstream explicitly supports different bridge and server versions. Microsoft ODBC Driver 18 is pinned to `18.6.2.1-1`, and SQL Server to `2022-CU26-ubuntu-22.04`.

These are public local demonstration credentials. ClickHouse HTTP binds only to `127.0.0.1:18123`; SQL Server, native ClickHouse, and the ODBC bridge publish no host ports. The SQL client trusts the demo server's self-signed certificate with `-C`; the ODBC DSN similarly enables encryption but uses `TrustServerCertificate=yes`. These local trust settings do not verify the server's identity. Developer Edition and the Compose setup are for development/testing. Building the driver and starting SQL Server accept the corresponding Microsoft EULAs through `ACCEPT_EULA=Y`.

## Start, load, and verify

Run the complete block from `docker-compose-recipes/recipes/ch-and-mssql`. Start from empty volumes for the first run; reset instructions follow.

```sh
set -eu
docker compose up -d --build --wait --wait-timeout 240

# The health checks query each database; sqlcmd fails on SQL errors (-b).
docker compose exec -T mssql sh -c '/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C -b -l 5 -t 30 -i /fixtures/fixture.sql'
docker compose exec -T mssql sh -c '/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C -b -l 5 -t 10 -Q "SELECT @@VERSION"'
docker compose exec -T clickhouse dpkg-query -W clickhouse-odbc-bridge unixodbc msodbcsql18

q() {
  docker compose exec -T clickhouse timeout 35 clickhouse-client \
    --user demo --password local-example-password \
    --connect_timeout 3 --receive_timeout 30 --max_execution_time 20 --query "$1"
}
q 'SELECT version()'

# The first ODBC request starts the bridge. Poll for its actual five-row result.
expected=$(cat fs/volumes/create-dataset/expected.tsv)
sql="SELECT customer_id, firstname, lastname, email, formatDateTime(created_date, '%F %T') FROM odbc('DSN=ch_mssql;Uid=sa;Pwd=Mssql_Password123', '', 'Customer') ORDER BY customer_id FORMAT TabSeparated"
attempt=0
actual=''
while [ "$attempt" -lt 20 ]; do
  attempt=$((attempt + 1))
  if actual=$(q "$sql") && [ "$actual" = "$expected" ]; then
    break
  fi
  sleep 2
done
if [ "$actual" != "$expected" ]; then
  printf 'ODBC fixture mismatch after %s attempts:\n%s\n' "$attempt" "$actual" >&2
  exit 1
fi
printf '%s\nOK: odbc() returned all 5 expected rows\n' "$actual"

# The table engine presents the same remote table under a ClickHouse name.
q "CREATE TABLE IF NOT EXISTS default.odbc_customer (customer_id Int32, firstname String, lastname String, email String, created_date DateTime) ENGINE = ODBC('DSN=ch_mssql;Uid=sa;Pwd=Mssql_Password123', '', 'Customer')"
actual=$(q 'SELECT * FROM default.odbc_customer ORDER BY customer_id FORMAT TabSeparated')
test "$actual" = "$expected"
printf 'OK: ODBC table engine returned the same 5 rows\n'
```

Both final assertions compare every fixture field, including all five dates. The expected customers are Jonah Hook, Mary Brown, Russell White, Dan Red, and Alice Black with IDs 1–5. The checked-in [expected TSV](./fs/volumes/create-dataset/expected.tsv) is the full expected output.

Compose waits up to 240 seconds after building for database health. SQL Server login/query timeouts bound its setup commands. ODBC readiness uses at most 20 attempts, with each ClickHouse client process limited to 35 seconds plus a 2-second interval. Errors return a nonzero status; inspect `docker compose logs --tail=100` when startup or queries fail. A failure to start SQL Server under emulation should be investigated on a supported native amd64 host before changing the database version.

The bridge is installed from the base image's signed ClickHouse apt repository, the driver from Microsoft's signed repository, and unixODBC from Ubuntu. Installing the separate bridge is required with current ClickHouse images. The empty middle ODBC argument uses the database configured in the DSN and SQL Server's default schema. The driver package registers its architecture-specific library, and [odbc.ini](./fs/volumes/clickhouse/odbc/odbc.ini) supplies the Compose DNS endpoint and source database.

## Rerun and reset

The fixture command **drops and recreates `ClickHouseDemo.dbo.Customer`** in a transaction, then inserts the same five rows. Repeating the walkthrough replaces this demonstration table without duplicates. The ClickHouse `odbc_customer` table is only a remote-table definition; it does not store a copy of the source data.

`docker compose down` stops the services and preserves their named volumes. For a completely fresh run, this command **deletes both databases' local data** for this Compose project:

```sh
docker compose down -v --remove-orphans
```

After changing `CHVER` or the Dockerfile, rebuild with `docker compose up -d --build --wait --wait-timeout 240`.

## ClickHouse Cloud counterpart

This recipe installs an ODBC driver inside a self-managed ClickHouse server. For an ingestion path into ClickHouse Cloud, export SQL Server data to Parquet/CSV in Azure Blob Storage, for example with Azure Data Factory, then ingest those files using the [Azure Blob Storage ClickPipes connector](https://clickhouse.com/docs/integrations/clickpipes/object-storage/azure-blob-storage/overview). This is file ingestion rather than live federated SQL or automatic SQL Server CDC. Plan incremental exports and updates/deletes according to your application; creating an object-storage ClickPipe does not make a SQL Server change stream.

See the [Azure Data Factory integration guide](https://clickhouse.com/docs/integrations/connectors/data-ingestion/azure/azure-data-factory) for the export/ingestion pattern. No Azure or ClickHouse Cloud resources are created by this local example.

## Validation and primary sources

Manually verified on 2026-09-06 on OrbStack: native Linux arm64 ClickHouse `26.8.2.7`, ODBC bridge `25.1.5.31`, Microsoft ODBC Driver `18.6.2.1-1`, and unixODBC `2.3.9-5ubuntu0.1`; SQL Server 2022 CU26 (`16.0.4265.3`) ran as **amd64 under emulation**. Container build, database readiness, the five-row fixture, and exact `odbc()`/ODBC-table assertions passed. The first ODBC request needed the documented startup retry. This records an emulated local run, not Microsoft-supported native arm64 SQL Server validation.

- [Microsoft container support and tools18 client](https://learn.microsoft.com/en-us/sql/linux/containers/deploy?view=sql-server-ver17)
- [SQL Server Docker quickstart](https://learn.microsoft.com/en-us/sql/linux/quickstart-install-connect-docker?view=sql-server-ver16)
- [Separate ClickHouse ODBC bridge and version compatibility](https://github.com/ClickHouse/odbc-bridge)
- [ClickHouse ODBC table function](https://clickhouse.com/docs/sql-reference/table-functions/odbc)
- [Microsoft ODBC Driver 18 installation](https://learn.microsoft.com/en-us/sql/connect/odbc/linux-mac/installing-the-microsoft-odbc-driver-for-sql-server?view=sql-server-ver17)
