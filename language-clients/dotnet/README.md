# C# / .NET client tour: ClickHouse.Driver

[`ClickHouse.Driver`](https://www.nuget.org/packages/ClickHouse.Driver) is the official
C# client. It speaks the compressed binary protocol over HTTP(S) and is the renamed
successor of `ClickHouse.Client`, now with a high-level `ClickHouseClient` facade on top
of the original ADO.NET surface (`ClickHouseDataSource`, `ClickHouseConnection`,
`ClickHouseDataReader`). This example pins **1.4.0** and targets **net10.0**; the package
supports .NET 6.0, 8.0, 9.0 and 10.0, so lowering `<TargetFramework>` to `net8.0` works
if that is the runtime you have.

## Prerequisites

- .NET SDK 10.0 (or 8.0 with the target framework changed to `net8.0`).
- A provisioned ClickHouse Cloud service and a `.env` file, per the [parent README](../README.md).
- You need a ClickHouse Cloud account. [Sign up at clickhouse.com/cloud](https://clickhouse.com/cloud) to start a free trial with $300 in credits.

## Run

```sh
set -a; source ../.env; set +a
./run.sh
```

## What the code does

1. **Connect and ping** — one `ClickHouseClient` built from `ClickHouseClientSettings`
   (`Protocol = "https"`, port from `CLICKHOUSE_HTTPS_PORT`), then
   `ExecuteScalarAsync("SELECT version()")`. The client is thread safe and holds the
   pooled `HttpClient`, so it is created once and disposed at the end.
2. **Create the table** — two `ExecuteNonQueryAsync` calls for the `DROP` and the
   `CREATE TABLE`.
3. **Insert** — `RegisterBinaryInsertType<Reading>()` compiles a RowBinary serializer for
   the POCO once, then ten `InsertBinaryAsync(table, rows, options)` calls stream 1,000
   `Reading` objects each. The driver reads the table schema once (cached) to pick column
   encoders, so `Guid`, `DateTime`, `double?`, `byte`, `string[]` and
   `Dictionary<string, string>` map straight onto `UUID`, `DateTime64(3, 'UTC')`,
   `Nullable(Float64)`, `UInt8`, `Array(String)` and `Map(String, String)`.
4. **Parameterized query** — a `ClickHouseParameterCollection` with `AddParameter` and
   native `{device:String}` / `{min_temp:Float64}` placeholders, bound server side.
5. **Stream** — `ExecuteReaderAsync` returns a `ClickHouseDataReader` that reads forward
   over the still-open HTTP response, so `await reader.ReadAsync()` materialises one row
   at a time. Columns come back through `GetGuid`, `GetDateTime`, `GetDouble`, `GetByte`,
   `IsDBNull` and `GetFieldValue<string[]>` / `GetFieldValue<Dictionary<string, string>>`.
6. **Aggregate** — `RegisterPocoType<SiteSummary>()` plus
   `QueryAsync<SiteSummary>(sql)`, an `IAsyncEnumerable<T>` that maps each row onto the
   typed class as it arrives.
7. **Error** — `ClickHouseServerException` derives from `DbException`, so the ClickHouse
   error code arrives in the inherited `ErrorCode` property; no message parsing needed.

## Notes

- Read POCOs need settable properties. `RegisterPocoType<T>()` throws
  `InvalidOperationException` if every mapped property is `init`-only or read-only, so
  `SiteSummary` uses `get; set;` while the insert-only `Reading` can stay `init`-only.
  For the same reason step 6 uses a class rather than a `record`.
- ClickHouse columns are snake_case and C# properties are PascalCase, so both POCOs
  annotate every property with `[ClickHouseColumn(Name = "...")]`.
- `count()` is `UInt64`, which maps to `ulong`, not `long`.
- Compression is on by default (`UseCompression = true`), and `InsertBinaryAsync` returns
  the number of rows the driver wrote, which step 3 sums across the ten batches.

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
