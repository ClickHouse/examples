# Go client tour: clickhouse-go

[`clickhouse-go/v2`](https://github.com/ClickHouse/clickhouse-go) is the official Go
client. It talks the native ClickHouse TCP protocol rather than HTTP, and this example
uses its native API (`clickhouse.Open`, `PrepareBatch`/`AppendStruct`, `Query`/`QueryRow`)
rather than the `database/sql` driver it also ships, because the native API exposes
typed batch inserts, server-side query parameters and structured server exceptions
directly, without going through `database/sql`'s generic, string-oriented interfaces.
The module is pinned to `github.com/ClickHouse/clickhouse-go/v2 v2.48.0`, whose own
`go.mod` requires Go 1.25.0.

## Prerequisites

- Go 1.25 or newer.
- A provisioned ClickHouse Cloud service and a `.env` file, both set up by the
  parent [`../README.md`](../README.md).
- You need a ClickHouse Cloud account. [Sign up at clickhouse.com/cloud](https://clickhouse.com/cloud) to start a free trial with $300 in credits.

## Run

```sh
set -a; source ../.env; set +a
./run.sh
```

## What the code does

1. **Connect and ping.** `clickhouse.Open` with `TLS: &tls.Config{}` opens a native
   TCP+TLS connection on `CLICKHOUSE_NATIVE_PORT`. `conn.QueryRow("SELECT version()").Scan(...)`
   confirms the connection with a real query.
2. **Create the table.** `conn.Exec` runs the `DROP TABLE IF EXISTS` and `CREATE TABLE`
   DDL statements directly; no query builder involved.
3. **Insert 10,000 rows in 10 batches.** `conn.PrepareBatch` opens a batch, and
   `batch.AppendStruct` serializes a `Reading` struct straight to the native column
   format for each of the 1,000 rows, matching columns via `ch:"..."` struct tags
   (the driver matches struct fields to column names by exact string equality, so
   the snake_case columns need explicit tags). `batch.Send()` flushes each batch.
4. **Parameterized query.** `clickhouse.Context(ctx, clickhouse.WithParameters(clickhouse.Parameters{...}))`
   binds `device` and `min_temp` as genuine server-side parameters; the SQL keeps the
   `{device:String}` / `{min_temp:Float64}` placeholders from the spec unchanged.
5. **Stream all rows back.** `conn.Query` opens a result stream and `rows.Next()`/`rows.Scan()`
   pulls one row at a time off the wire into native Go types (`uuid.UUID`, `time.Time`,
   `*float64`, `[]string`, `map[string]string`), so the 10,000 rows are never buffered
   into a slice.
6. **Aggregate into typed results.** `rows.ScanStruct(&s)` maps each grouped row onto a
   `SiteSummary` struct using the same `ch`-tag field matching as step 3.
7. **Handle a server error.** The failing query's error is unwrapped with
   `errors.As(err, &chErr)` into a `*clickhouse.Exception`, whose `Code` field holds
   the ClickHouse error code directly (no message parsing needed).

## Notes

- **`ch` tags are mandatory, not cosmetic.** `AppendStruct`/`ScanStruct` match struct
  fields to column names by exact, case-sensitive string comparison. Since Go fields
  must be exported (capitalized) and the table's columns are snake_case, every field
  needs a `ch:"column_name"` tag or the match silently fails to find the column.
- **`clickhouse.Conn` is a type alias** for `github.com/ClickHouse/clickhouse-go/v2/lib/driver.Conn`,
  so the top-level `clickhouse` package is the only import needed for the connection type.
- **TLS config.** An empty `&tls.Config{}` is enough for ClickHouse Cloud: it verifies
  the server certificate against the system trust store and enables SNI from the `Addr`
  host. No custom CA or `InsecureSkipVerify` is needed.

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
