"""ClickHouse client tour: clickhouse-connect.

Runs the seven steps described in ../SPEC.md against one ClickHouse Cloud
service, using the official synchronous `clickhouse-connect` client over
HTTPS. See README.md for a step-by-step explanation.
"""

import os
import sys
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

import clickhouse_connect
from clickhouse_connect.driver.exceptions import DatabaseError

TABLE = "readings_python"
ERROR_TABLE = "no_such_table_python"
SITES = ["amsterdam", "berlin", "london", "madrid", "paris"]

REQUIRED_ENV_VARS = [
    "CLICKHOUSE_HOST",
    "CLICKHOUSE_HTTPS_PORT",
    "CLICKHOUSE_USER",
    "CLICKHOUSE_PASSWORD",
    "CLICKHOUSE_DATABASE",
]


def read_env() -> dict:
    missing = [name for name in REQUIRED_ENV_VARS if not os.environ.get(name)]
    if missing:
        print(f"missing required environment variable(s): {', '.join(missing)}", file=sys.stderr)
        sys.exit(1)
    return {name: os.environ[name] for name in REQUIRED_ENV_VARS}


def build_row(i: int) -> list:
    """Build one telemetry row using only integer arithmetic plus a single
    final division per float column, so every language client produces the
    same bit-for-bit doubles."""
    reading_id = uuid.UUID(f"00000000-0000-4000-8000-{i:012x}")
    recorded_at = datetime(2026, 1, 1, tzinfo=timezone.utc) + timedelta(
        milliseconds=i * 1000 + (i * 37) % 1000
    )
    device_num = i % 50
    device_id = f"device-{device_num:02d}"
    site = SITES[device_num % 5]
    temp_c = 15.0 + ((i * 7919) % 1997) / 100.0
    humidity_pct = None if i % 10 == 0 else 30.0 + ((i * 104729) % 6000) / 100.0
    battery_pct = 100 - (i % 101)
    if i % 3 == 0:
        tags = ["calibrated"]
    elif i % 3 == 1:
        tags = ["calibrated", "outdoor"]
    else:
        tags = []
    attributes = {
        "firmware": f"1.{i % 4}",
        "model": "tx-100" if i % 2 == 0 else "tx-200",
    }
    return [
        reading_id,
        recorded_at,
        device_id,
        site,
        temp_c,
        humidity_pct,
        battery_pct,
        tags,
        attributes,
    ]


@dataclass
class SiteAggregate:
    site: str
    readings: int
    avg_temp_c: float
    max_temp_c: float


def main() -> None:
    env = read_env()
    table = f"{env['CLICKHOUSE_DATABASE']}.{TABLE}"
    error_table = f"{env['CLICKHOUSE_DATABASE']}.{ERROR_TABLE}"

    client = clickhouse_connect.get_client(
        host=env["CLICKHOUSE_HOST"],
        port=int(env["CLICKHOUSE_HTTPS_PORT"]),
        username=env["CLICKHOUSE_USER"],
        password=env["CLICKHOUSE_PASSWORD"],
        database=env["CLICKHOUSE_DATABASE"],
        secure=True,
    )

    # 1. Connect and ping
    version = client.query("SELECT version()").result_rows[0][0]
    print(f"1 connect: ok, server version {version}")

    # 2. Create the table
    client.command(f"DROP TABLE IF EXISTS {table}")
    client.command(
        f"""
        CREATE TABLE {table}
        (
            reading_id   UUID,
            recorded_at  DateTime64(3, 'UTC'),
            device_id    LowCardinality(String),
            site         LowCardinality(String),
            temp_c       Float64,
            humidity_pct Nullable(Float64),
            battery_pct  UInt8,
            tags         Array(String),
            attributes   Map(String, String)
        )
        ENGINE = MergeTree
        ORDER BY (site, device_id, recorded_at)
        """
    )
    print("2 create table: ok")

    # 3. Insert 10,000 typed rows in 10 batches
    column_names = [
        "reading_id",
        "recorded_at",
        "device_id",
        "site",
        "temp_c",
        "humidity_pct",
        "battery_pct",
        "tags",
        "attributes",
    ]
    batches = 10
    batch_size = 1000
    for batch in range(batches):
        start = batch * batch_size
        rows = [build_row(i) for i in range(start, start + batch_size)]
        client.insert(table, rows, column_names=column_names)
    print(f"3 insert: {batches * batch_size} rows in {batches} batches")

    # 4. Parameterized query. clickhouse-connect passes `parameters` through
    # to the server as query parameters, so {device:String} and
    # {min_temp:Float64} are bound server-side, not string-formatted.
    result = client.query(
        f"""
        SELECT count() FROM {table}
        WHERE device_id = {{device:String}} AND temp_c > {{min_temp:Float64}}
        """,
        parameters={"device": "device-07", "min_temp": 30.0},
    )
    count = result.result_rows[0][0]
    print(f"4 parameterized query: {count} readings for device-07 above 30.0 C")

    # 5. Stream all rows back. query_rows_stream returns rows one at a time
    # over the HTTP response as it is read, rather than buffering the whole
    # result set, and must be used as a context manager so the underlying
    # connection is released once the loop ends or raises.
    row_count = 0
    battery_total = 0
    humidity_null_count = 0
    tag_count = 0
    with client.query_rows_stream(f"SELECT * FROM {table} ORDER BY recorded_at") as stream:
        for row in stream:
            _, _, _, _, _, humidity_pct, battery_pct, tags, _ = row
            row_count += 1
            battery_total += battery_pct
            if humidity_pct is None:
                humidity_null_count += 1
            tag_count += len(tags)
    print(
        f"5 stream: {row_count} rows, battery total {battery_total}, "
        f"humidity null in {humidity_null_count} rows, {tag_count} tags"
    )

    # 6. Aggregate into typed results
    aggregate_result = client.query(
        f"""
        SELECT site, count() AS readings,
               round(avg(temp_c), 2) AS avg_temp_c,
               round(max(temp_c), 2) AS max_temp_c
        FROM {table}
        GROUP BY site ORDER BY site
        """
    )
    aggregates = [SiteAggregate(**row) for row in aggregate_result.named_results()]
    print("6 aggregate: site readings avg_temp_c max_temp_c")
    for agg in aggregates:
        print(f"6 aggregate: {agg.site} {agg.readings} {agg.avg_temp_c:.2f} {agg.max_temp_c:.2f}")

    # 7. Handle a server error. clickhouse-connect populates the DatabaseError
    # subclass's `code` attribute from the X-ClickHouse-Exception-Code
    # response header, so there is no need to parse "Code: 60" out of the
    # message text.
    try:
        client.query(f"SELECT count() FROM {error_table}")
    except DatabaseError as err:
        print(f"7 error: server error code {err.code}")

    client.close()


if __name__ == "__main__":
    main()
