from dagster import Definitions, ScheduleDefinition, op, job
from clickhouse_driver import Client


client = Client("clickhouse")


@op
def fill_op():
    client.execute("""
        CREATE TABLE test
        (
            user_id UInt32,
            message String,
            metric Float32
        )
        ENGINE = MergeTree
        PRIMARY KEY (user_id)
    """)
    client.execute("""
    INSERT INTO test (user_id, message, metric) VALUES
        (101, 'Hello, ClickHouse!',                                 -1.0    ),
        (102, 'Insert a lot of rows per batch',                     1.41421 ),
        (102, 'Sort your data based on your commonly-used queries', 2.718   ),
        (101, 'Granules are the smallest chunks of data read',      3.14159 )
    """)


@job
def fill():
    fill_op()


@op
def show_op():
    r = client.execute("select * from test")
    print(r)


@job
def show():
    show_op()


definitions = Definitions(jobs=[show,fill])
