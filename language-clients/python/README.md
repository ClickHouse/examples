# Python client tour: clickhouse-connect

[`clickhouse-connect`](https://github.com/ClickHouse/clickhouse-connect) is ClickHouse's official Python driver. It speaks the HTTP(S) protocol and exchanges data with the server in ClickHouse's native columnar format, so inserts and query results move as typed columns rather than text. This tour pins `clickhouse-connect==1.8.0` and runs on Python 3.10 through 3.14. The package also ships optional integrations for pandas, Polars, and Arrow, plus an `AsyncClient`, but this tour sticks to the plain synchronous `Client` and Python lists so the client's core API stays visible.

## Prerequisites

- Python 3.10+ (tested with 3.14)
- A provisioned ClickHouse Cloud service and a `.env` file in the parent directory — see [../README.md](../README.md)

You need a ClickHouse Cloud account. [Sign up at clickhouse.com/cloud](https://clickhouse.com/cloud) to start a free trial with $300 in credits.

## Run

```sh
set -a; source ../.env; set +a
./run.sh
```

## What the code does

1. **Connect and ping** — `clickhouse_connect.get_client(..., secure=True)` opens an HTTPS connection on `CLICKHOUSE_HTTPS_PORT`; `client.query("SELECT version()")` confirms it and reads back the server version.
2. **Create the table** — `client.command(...)` runs the `DROP TABLE IF EXISTS` and `CREATE TABLE` DDL statements.
3. **Insert 10,000 rows** — each row is built as a plain Python list (`uuid.UUID`, timezone-aware `datetime`, `str`, `float`, `list[str]`, `dict[str, str]`) and sent with `client.insert(table, rows, column_names=[...])`, ten calls of 1,000 rows each. No SQL strings are built for the data.
4. **Parameterized query** — `client.query(sql, parameters={"device": "device-07", "min_temp": 30.0})` binds both values server-side using the `{device:String}` / `{min_temp:Float64}` syntax in the SQL text; clickhouse-connect forwards the `parameters` dict as ClickHouse query parameters rather than formatting the string client-side.
5. **Stream all rows back** — `with client.query_rows_stream(sql) as stream: for row in stream:` reads rows off the HTTP response as they arrive instead of buffering the full result set; the loop accumulates row count, battery total, null-humidity count, and tag count.
6. **Aggregate into typed results** — `client.query(sql).named_results()` yields one `dict` per row, which is unpacked into a `SiteAggregate` dataclass before printing.
7. **Handle a server error** — the bad query is wrapped in `try/except DatabaseError`. clickhouse-connect's `DatabaseError` (and its base `Error` class) exposes a `.code` attribute populated straight from the `X-ClickHouse-Exception-Code` response header, so the code is read directly rather than parsed out of the message text.

## Notes

- `DatabaseError.code` is populated natively by clickhouse-connect 1.8.0 from the response header, so step 7 does not need to parse `Code: 60` out of the exception message.
- The row generator uses a modulus of 1997 (not 2000) for `temp_c`, per SPEC.md: with 2000 the per-site mean temperature lands exactly on a `.xx5` rounding boundary, and `round(avg(Float64), 2)` can then flip depending on the server's floating-point summation order across parts and threads. 1997 keeps every site mean safely off that boundary.

## Expected output

```
1 connect: ok, server version <version>
2 create table: ok
3 insert: 10000 rows in 10 batches
4 parameterized query: 48 readings for device-07 above 30.0 C
5 stream: 10000 rows, battery total 500050, humidity null in 1000 rows, 10000 tags
6 aggregate: site readings avg_temp_c max_temp_c
6 aggregate: amsterdam 2000 24.98 34.96
6 aggregate: berlin 2000 24.99 34.96
6 aggregate: london 2000 24.99 34.96
6 aggregate: madrid 2000 24.99 34.96
6 aggregate: paris 2000 24.99 34.96
7 error: server error code 60
```
