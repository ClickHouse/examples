import os
from contextlib import contextmanager

from clickhouse_driver import Client
from dagster import Definitions, job, op


# Exact binary fractions keep the Float64 fixture comparison deterministic.
ROWS = [
    (101, "Hello, ClickHouse!", -1.0),
    (102, "Insert rows in batches", 1.5),
    (103, "Sort by common query keys", 2.75),
    (104, "Read data in granules", 3.125),
]


@contextmanager
def connection():
    client = Client(
        host=os.environ["CLICKHOUSE_HOST"],
        port=int(os.environ["CLICKHOUSE_PORT"]),
        user=os.environ["CLICKHOUSE_USER"],
        password=os.environ["CLICKHOUSE_PASSWORD"],
        secure=os.environ.get("CLICKHOUSE_SECURE", "false").lower() == "true",
        connect_timeout=5,
        send_receive_timeout=15,
        settings={"max_execution_time": 10},
    )
    try:
        yield client
    finally:
        client.disconnect()


@op
def fill_op(context):
    with connection() as client:
        client.execute("""
            CREATE TABLE IF NOT EXISTS dagster_demo
            (user_id UInt32, message String, metric Float64)
            ENGINE = MergeTree ORDER BY user_id
        """)
        # This is a replacement fixture, not an append-only ingestion job.
        client.execute("TRUNCATE TABLE dagster_demo")
        client.execute("INSERT INTO dagster_demo VALUES", ROWS)
    context.log.info("Replaced dagster_demo with 4 fixture rows")


@job
def fill():
    fill_op()


@op
def show_op(context):
    with connection() as client:
        rows = client.execute(
            "SELECT user_id, message, metric FROM dagster_demo ORDER BY user_id"
        )
    if rows != ROWS:
        raise ValueError(f"Expected exactly {ROWS!r}; got {rows!r}")
    for row in rows:
        context.log.info(str(row))
    context.log.info("OK: exactly 4 expected rows")


@job
def show():
    show_op()


definitions = Definitions(jobs=[fill, show])
