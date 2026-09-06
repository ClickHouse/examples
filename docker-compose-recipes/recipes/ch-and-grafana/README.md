# ClickHouse and Grafana

One ClickHouse server feeds a provisioned Grafana dashboard through the official ClickHouse data source plugin. A checked-in fixture contains three invented orders; the **Order total** stat panel must display **45**. This demonstrates data source provisioning and a query-backed panel, not a production monitoring deployment.

Grafana requires login as `admin` / `local-grafana-password`; anonymous access is disabled. ClickHouse's demonstration administrator is `demo` / `local-example-password`, while Grafana connects as `grafana_reader` / `local-reader-password` with SELECT access only to `default.events`. These are public development credentials, and local traffic is not encrypted. Published ports bind to loopback; do not expose the recipe on a shared host or reuse these passwords.

## Prerequisites and versions

Use Docker Engine/Desktop or OrbStack with Docker Compose v2. Allocate roughly 4 GiB of Docker memory, 2 CPUs, and several GiB of free disk. Linux amd64 and arm64 images are published; Docker runs them in a Linux VM on macOS/Windows. No host npm, pip, Grafana, or ClickHouse client installation is required.

Grafana is pinned to **13.2.1**, and `grafana-clickhouse-datasource` to **4.21.2**. Grafana installs this exact signed plugin synchronously inside its container before provisioning, so the first start requires access to the Grafana plugin catalog. ClickHouse keeps the `${CHVER:-latest}` default; export `CHVER` before starting to override it. Floating tags are not compatibility guarantees.

Last manually verified: **2026-09-06**, ClickHouse **26.8.2.7**, Grafana **13.2.1**, ClickHouse plugin **4.21.2**, Linux **aarch64** on OrbStack (Docker 29.4.0 / Compose 5.1.2). From empty volumes, data source and dashboard provisioning passed and the actual panel query returned **45**. This is a single-platform manual check.

## Start and verify

From this directory, run:

```sh
set -eu
docker compose up -d
docker compose exec -T clickhouse clickhouse-client \
  --user demo --password local-example-password --query 'SELECT version()'
docker compose run --rm --no-deps verify
```

ClickHouse readiness checks the seeded table through the same reader account Grafana uses. The manual verification container waits up to 180 seconds for Grafana, the plugin, data source, and dashboard; each API request has a 15-second timeout. It then retrieves the provisioned dashboard and submits **that panel's SQL target** to Grafana's data source query API. HTTP failures, API errors, or a result other than 45 fail visibly. Inspect `docker compose logs --tail=100` if verification fails.

Expected output includes the actual ClickHouse version, Grafana `13.2.1`, plugin `4.21.2`, and:

```text
OK: datasource and dashboard provisioned; Order total panel query returned 45
```

Open [the orders dashboard](http://localhost:13000/d/clickhouse-example) and log in with the Grafana credentials above. Its SQL is deliberately independent of the dashboard time range:

```sql
SELECT sum(amount) AS total FROM default.events
```

The included orders have amounts 10, 20, and 15. The API verification checks the panel's returned data; it does not claim to test browser rendering or supply a new screenshot.

## Stop, rerun, and reset

The verification command is safe to repeat. `docker compose stop` preserves the ClickHouse/Grafana volumes; `docker compose up -d` resumes them. For an empty-state rerun:

```sh
docker compose down -v --remove-orphans
```

This is destructive: it deletes the ClickHouse tables and Grafana database, saved user changes, and downloaded plugin files. Checked-in fixture/provisioning/dashboard files remain. Repeat the start/verify block; the fixture is loaded once when the ClickHouse data volume is first initialized.

## ClickHouse Cloud equivalent

Use the same Grafana ClickHouse plugin with a ClickHouse Cloud service. Create the example table and a dedicated SELECT-only account in that service, then configure its real hostname, credentials, and TLS: native protocol port **9440**, `secure: true`, and certificate verification enabled. Allow connections from your Grafana deployment in the Cloud service's network settings. Use Grafana Cloud if you also want managed dashboards; neither Cloud product can reach the Compose hostname `clickhouse`.

- [ClickHouse Grafana integration](https://clickhouse.com/docs/integrations/grafana)
- [ClickHouse data source configuration](https://grafana.com/docs/plugins/grafana-clickhouse-datasource/latest/configure/)
- [Grafana synchronous plugin installation](https://grafana.com/docs/grafana/latest/setup-grafana/configure-grafana/#preinstall_sync)
- [Grafana provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/)
- [Grafana data source query API](https://grafana.com/docs/grafana/latest/developer-resources/api-reference/http-api/api-legacy/data_source/)
