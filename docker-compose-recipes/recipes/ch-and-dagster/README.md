# ClickHouse + Dagster

Run two Dagster jobs against ClickHouse: `fill` replaces a small fixture and `show` reads and verifies it. The stack contains one ClickHouse server and one Dagster development process (web UI, daemon, and user code). Keeper is unnecessary for this single-server MergeTree lesson.

This is a local development example. The Dagster UI has no authentication, and the ClickHouse password is a public demonstration credential. Both published ports bind to loopback. `dagster dev` is a development launcher; use a supported Dagster deployment and ClickHouse Cloud for a production application.

## Requirements

Use Docker with Compose v2 and a POSIX shell, with about 2 CPUs, 4 GiB of memory and a few GiB of free disk available to Docker. The first build downloads Python packages **inside the container**. No host Python, pip, npm, or database client installation is needed.

The Python and ClickHouse base images support Linux amd64 and arm64. Only the platform recorded below has been manually verified. ClickHouse defaults to `latest`; set `CHVER` to select another version. Dagster and `dagster-webserver` are pinned to `1.13.21`, and `clickhouse-driver` to `0.2.11`.

## Start, import, fill, show, and repeat

Run this complete block from `docker-compose-recipes/recipes/ch-and-dagster`. Start from empty volumes for the first walkthrough; see reset below if you have run it before.

```sh
set -eu
docker compose up -d --build

# ClickHouse's health check gates Dagster startup. Poll its UI for at most
# 60 attempts, each with a 3-second HTTP timeout and a 2-second interval.
docker compose exec -T dagster_webserver python - <<'PY'
import time
import urllib.error
import urllib.request
for attempt in range(60):
    try:
        with urllib.request.urlopen("http://127.0.0.1:3000/server_info", timeout=3) as response:
            if response.status == 200:
                print("Dagster webserver ready")
                break
    except (urllib.error.URLError, TimeoutError):
        pass
    time.sleep(2)
else:
    raise SystemExit("Dagster webserver did not become ready")
PY

docker compose exec -T clickhouse clickhouse-client --user demo --password local-example-password --query 'SELECT version()'
docker compose exec -T dagster_webserver python - <<'PY'
from importlib.metadata import version
from dagster import Definitions
from user_code import definitions
Definitions.validate_loadable(definitions)
for name in ("dagster", "dagster-webserver", "clickhouse-driver"):
    print(f"{name} {version(name)}")
print("OK: user_code imports and definitions are loadable")
PY

docker compose exec -T dagster_webserver dagster job list -m user_code
docker compose exec -T dagster_webserver dagster job execute -m user_code -j fill
docker compose exec -T dagster_webserver dagster job execute -m user_code -j show

# Fill replaces the fixture, so a second fill must still produce four rows.
docker compose exec -T dagster_webserver dagster job execute -m user_code -j fill
docker compose exec -T dagster_webserver dagster job execute -m user_code -j show
test "$(docker compose exec -T clickhouse clickhouse-client --user demo --password local-example-password --query 'SELECT count() FROM dagster_demo')" = 4
printf 'OK: repeated fill still has exactly 4 rows\n'
```

`show` compares all four rows in `user_id` order, including messages and metrics, and raises an error on any mismatch. Each run must log `OK: exactly 4 expected rows` and finish successfully. The expected rows are:

| user_id | message | metric |
| --- | --- | --- |
| 101 | Hello, ClickHouse! | -1 |
| 102 | Insert rows in batches | 1.5 |
| 103 | Sort by common query keys | 2.75 |
| 104 | Read data in granules | 3.125 |

Open [the Dagster UI](http://localhost:13000) to inspect the run history or launch `fill` and then `show` manually. ClickHouse HTTP is available at `localhost:18123`; native connections from Dagster stay inside the Compose network on port 9000.

`fill` runs `CREATE TABLE IF NOT EXISTS`, `TRUNCATE`, then one batch insert. Every run **deletes existing data in `default.dagster_demo`** before loading the fixture. Run these jobs sequentially: this reset is not transactional, and concurrent `fill`/`show` runs can observe an empty or changing table. It is a repeatable demonstration, not a general ingestion retry strategy. Driver connections have a 5-second connection timeout and 15-second send/receive timeout; queries have a 10-second execution limit. Errors make the job and CLI exit unsuccessfully.

If startup or a job fails, inspect `docker compose logs --tail=100` and the Dagster run logs. Source files are mounted read-only; editing `user_code/__init__.py` on the host updates the code available to the development server. Restart Dagster if needed to reload definitions.

## Stop and reset

`docker compose down` stops the services and retains ClickHouse data and Dagster history. The documented fill/show sequence can be repeated against that state.

To remove **all data and run history belonging to this Compose project**, then rerun the full walkthrough:

```sh
docker compose down -v --remove-orphans
```

After changing pinned dependencies or the Dockerfile, rebuild with `docker compose up -d --build`. If you change `dagster.yaml`, remove the Dagster volume during reset so the fresh image configuration is used.

## ClickHouse Cloud counterpart

Dagster can run these same jobs against a ClickHouse Cloud service using the driver's native TLS connection. In your Dagster deployment, set `CLICKHOUSE_HOST` to the service hostname, `CLICKHOUSE_PORT=9440`, `CLICKHOUSE_SECURE=true`, and provide its actual username/password through `CLICKHOUSE_USER` and `CLICKHOUSE_PASSWORD`. Allow the deployment's network address in the Cloud service settings. The example uses the `default` database; give the user permission to create, truncate, insert, and select the dedicated demonstration table.

Use a disposable table for this destructive fixture. ClickHouse Cloud replaces the database service; Dagster still runs the orchestration jobs. This recipe does not provision Cloud resources or validate a Cloud deployment.

## Validation and sources

Manually verified on 2026-09-06 with Linux arm64 containers on OrbStack: ClickHouse `26.8.2.7`, Dagster and `dagster-webserver` `1.13.21`, and `clickhouse-driver` `0.2.11`. The complete walkthrough passed from empty volumes: imports, job discovery, fill/show, repeated fill/show, and the exact four-row assertion. The CLI emits a supersession notice for `dagster job`, but these commands work with the pinned release.

- [Dagster CLI](https://docs.dagster.io/api/clis/cli)
- [Dagster Definitions](https://docs.dagster.io/api/dagster/definitions)
- [Dagster deployment overview](https://docs.dagster.io/deployment)
- [clickhouse-driver connection parameters](https://clickhouse-driver.readthedocs.io/en/latest/api.html)
- [ClickHouse Cloud connection details](https://clickhouse.com/integrations/clickhouse_client)
