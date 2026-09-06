# Node.js client tour: @clickhouse/client

[`@clickhouse/client`](https://www.npmjs.com/package/@clickhouse/client) is the
official ClickHouse client for Node.js. It speaks ClickHouse's HTTP protocol,
has zero runtime dependencies, and is pinned here at an exact version
(`1.23.1`). It supports Node.js 18 and newer; this example targets Node 22+.
For browsers and Cloudflare Workers, ClickHouse publishes a separate
[`@clickhouse/client-web`](https://www.npmjs.com/package/@clickhouse/client-web)
package instead — it is not used here.

## Prerequisites

- Node.js 22 or newer, and npm.
- A provisioned ClickHouse Cloud service and a `.env` file in the parent
  directory (see [`../README.md`](../README.md)).

You need a ClickHouse Cloud account. [Sign up at clickhouse.com/cloud](https://clickhouse.com/cloud)
to start a free trial with $300 in credits.

## Run

```sh
set -a; source ../.env; set +a
./run.sh
```

## What the code does

1. **Connect and ping** — `createClient({ url: 'https://host:port', username, password, database })`
   opens the client, then `client.query({ query: 'SELECT version()' })` confirms
   the server is reachable and reads its version.
2. **Create the table** — `client.command()` runs the `DROP TABLE IF EXISTS`
   and `CREATE TABLE` statements. `command()` is used instead of `insert()` or
   `query()` because DDL has no row payload and returns no result set.
3. **Insert 10,000 rows in 10 batches** — each row is generated as a plain
   JS object matching the `JSONEachRow` representation of its ClickHouse
   types (UUID and `Map` as strings/objects, `DateTime64(3)` as a
   `'YYYY-MM-DD HH:MM:SS.mmm'` string, the nullable column as `null`), and
   `client.insert({ table, values, format: 'JSONEachRow' })` sends each
   1,000-row batch.
4. **Parameterized query** — `client.query()` binds `device` and `min_temp`
   through `query_params` against `{device:String}` / `{min_temp:Float64}`
   placeholders in the SQL, so values are never interpolated into the query
   text.
5. **Stream all rows back** — `client.query({ format: 'JSONEachRow' }).stream()`
   returns a Node.js `Readable` of row-array chunks; the code `for await`s the
   stream and calls `row.json<ReadingRow>()` per row, accumulating counts as
   rows arrive instead of buffering the full result set.
6. **Aggregate into typed results** — the grouped `SELECT` is read with
   `.json<SiteStats[]>()` into a typed array and printed with `toFixed(2)`.
7. **Handle a server error** — the query against the missing table is wrapped
   in `try/catch`; the catch checks `err instanceof ClickHouseError` and
   prints `err.code`, which the client already exposes as the ClickHouse
   error code string (`'60'` for `UNKNOWN_TABLE`) without needing to parse
   the message.

## Notes

- **64-bit integers as strings.** ClickHouse's JSON output formats quote
  `UInt64`/`Int64` values as strings by default
  (`output_format_json_quote_64bit_integers=1`), to avoid precision loss in
  JS numbers. `count()` results (steps 4 and 6) are typed as `string` for
  this reason, not `number`.
- **Client-side error logging on stderr.** `@clickhouse/client` logs caught
  request errors (including the expected step 7 `UNKNOWN_TABLE` failure) to
  stderr via its own internal logger before the exception reaches
  application code. This is expected and matches the spec's stdout/stderr
  split — no application code logs to stderr here.

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
