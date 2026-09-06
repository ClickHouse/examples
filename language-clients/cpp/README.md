# C++ client tour: clickhouse-cpp

[`clickhouse-cpp`](https://github.com/ClickHouse/clickhouse-cpp) is the official C++ client for
ClickHouse. It speaks the native TCP protocol (with TLS when built against OpenSSL) and exposes
ClickHouse's column-oriented wire format directly: you read and write `Block`s of typed columns
such as `ColumnUUID`, `ColumnDateTime64` and `ColumnLowCardinalityT<ColumnString>` rather than
rows of strings. This example pulls in tag `v2.6.2` with CMake `FetchContent` and builds it from
source with `-DWITH_OPENSSL=ON`, which is what enables `ClientOptions::SetSSLOptions()`. The
library is under active development; a few types and conveniences are still missing, so check the
[issue tracker](https://github.com/ClickHouse/clickhouse-cpp/issues) if something is unsupported.

## Prerequisites

- CMake 3.16 or newer, and a C++17 compiler.
- OpenSSL development files (`brew install openssl@3` on macOS, `libssl-dev` on Debian/Ubuntu,
  `openssl-devel` on Fedora/RHEL). `run.sh` passes `-DOPENSSL_ROOT_DIR` automatically when
  Homebrew is on the `PATH`.
- Git, because `FetchContent` clones the library at configure time.
- A provisioned ClickHouse Cloud service and a `.env` file, per the [parent README](../README.md).

You need a ClickHouse Cloud account. [Sign up at clickhouse.com/cloud](https://clickhouse.com/cloud) to start a free trial with $300 in credits.

## Run

```sh
set -a; source ../.env; set +a
./run.sh
```

## What the code does

1. **Connect and ping.** `Client` is constructed from a `ClientOptions` chain; `SetSSLOptions({})`
   turns on TLS against the system CA store and the port is `CLICKHOUSE_NATIVE_PORT` (9440).
   `Ping()` opens the connection, then `Select("SELECT version()", cb)` reads the version out of a
   `ColumnString`.
2. **Create the table.** `Execute()` runs the `DROP` and `CREATE TABLE` statements; it returns no
   data.
3. **Insert 10,000 rows in 10 batches.** Each batch builds a `Block` from typed columns
   (`ColumnUUID`, `ColumnDateTime64(3, "UTC")`, `ColumnLowCardinalityT<ColumnString>`,
   `ColumnFloat64`, `ColumnNullableT<ColumnFloat64>`, `ColumnUInt8`, `ColumnArrayT<ColumnString>`,
   `ColumnMapT<ColumnString, ColumnString>`) and is sent with `Insert(table, block)`, which
   derives the `INSERT INTO ... VALUES` statement from the block's column names.
4. **Parameterized query.** A `Query` object carries the SQL plus `SetParam("device", ...)` and
   `SetParam("min_temp", ...)`, which the client sends as server-side query parameters for the
   `{device:String}` and `{min_temp:Float64}` placeholders.
5. **Stream all rows back.** `Select(sql, callback)` invokes the callback once per `Block` as it
   arrives off the socket, so nothing is buffered into a single result set. Each row is decoded
   into a `Reading` struct with `AsStrict<ColumnUUID>()`, `AsStrict<ColumnDateTime64>()` and
   friends, and the counters are accumulated as the rows go by.
6. **Aggregate into typed results.** The same `Select` callback, mapping each block row into a
   `SiteStats` struct that is printed afterwards.
7. **Handle a server error.** `ClientOptions::rethrow_exceptions` defaults to true, so a query
   against a missing table throws `clickhouse::ServerException`; `GetCode()` returns the
   ClickHouse error code (60, `UNKNOWN_TABLE`).

## Notes

- **Parameters.** `Query::SetParam` sends genuine server-side parameters, so no escaping or string
  interpolation is involved. Values are passed as strings and cast by the server to the type named
  in the placeholder. Note that the plain `Client::Select(std::string, callback)` overload has no
  parameter argument; you have to build a `Query` and use `Client::Select(const Query&)` with
  `Query::OnData` for the result callback.
- **LowCardinality.** On the way in, `ColumnLowCardinalityT<ColumnString>` gives a typed
  `Append(std::string)`. On the way out the server's `LowCardinality(String)` columns are
  materialised as plain `ColumnLowCardinality`, so `As<ColumnLowCardinalityT<ColumnString>>()`
  returns null. The typed wrapper is only reachable through `ColumnLowCardinalityT<...>::Wrap()`,
  which steals the column's internals, so this example instead reads values with
  `ColumnLowCardinality::GetItem(row).get<std::string_view>()`, which is non-destructive.
  `Nullable(T)`, `Array(T)` and `Map(K, V)` behave the same way: they come back as `ColumnNullable`,
  `ColumnArray` and `ColumnMap`, and are read through `Nested()`, `GetAsColumnTyped<T>()` and
  `GetAsColumn()` respectively.
- **Batching.** Each batch here is its own `Client::Insert()` call, so ten `INSERT` statements are
  issued. For much larger loads the library also offers
  `BeginInsert()` / `SendInsertBlock()` / `EndInsert()`, which streams any number of blocks inside
  a single `INSERT` statement; the server then squashes them into one part instead of creating one
  part per call.
- **First build.** `FetchContent` clones clickhouse-cpp and compiles it, along with its vendored
  abseil, cityhash, lz4 and zstd, so the first `./run.sh` takes noticeably longer than later ones.
  Everything is cached under `build/`.

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
