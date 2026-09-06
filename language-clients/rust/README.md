# Rust client tour: clickhouse crate

[`clickhouse`](https://crates.io/crates/clickhouse) is the official Rust client
([ClickHouse/clickhouse-rs](https://github.com/ClickHouse/clickhouse-rs)). It talks
HTTP(S) and encodes rows as `RowBinaryWithNamesAndTypes`, mapping them to your own
structs through `serde` and a `#[derive(Row)]` macro that records the field names so
the client can validate them against the server's schema. This example pins
`clickhouse = "=0.15.2"` with the `rustls-tls`, `uuid` and `time` features, on `tokio`.
The crate's MSRV is Rust 1.89 and it is published for edition 2024.

## Prerequisites

- A Rust toolchain (1.89 or newer; `cargo` 1.93 was used here).
- A provisioned ClickHouse Cloud service and a `.env` file, both set up by the
  parent [`../README.md`](../README.md).
- You need a ClickHouse Cloud account. [Sign up at clickhouse.com/cloud](https://clickhouse.com/cloud) to start a free trial with $300 in credits.

## Run

```sh
set -a; source ../.env; set +a
./run.sh
```

## What the code does

1. **Connect and ping.** `Client::default()` plus `with_url`/`with_user`/`with_password`/`with_database`;
   the `https://` URL and the `rustls-tls` feature are all that TLS needs. `query("SELECT version()").fetch_one::<String>()`
   reads a scalar straight into a Rust type.
2. **Create the table.** `query(...).execute()` for DDL. `sql::Identifier` binds the `?`
   placeholder as a quoted identifier rather than a string literal.
3. **Insert 10,000 rows in 10 batches.** `client.insert::<Reading>(table)` opens one
   streaming INSERT; `write(&row)` appends a row and `end()` flushes and awaits the
   server's response. `Reading` derives `Row + Serialize`, with
   `#[serde(with = "clickhouse::serde::uuid")]` for `UUID`,
   `clickhouse::serde::time::datetime64::millis` for `DateTime64(3)`, `Option<f64>` for
   `Nullable(Float64)`, `Vec<String>` for `Array(String)` and `Vec<(String, String)>`
   for `Map(String, String)`.
4. **Parameterized query.** `Query::param("device", ...)` sends real server-side query
   parameters, so the SQL keeps the `{device:String}` / `{min_temp:Float64}` placeholders
   from the spec.
5. **Stream all rows back.** `query(...).fetch::<Reading>()?` returns a `RowCursor`;
   `while let Some(row) = cursor.next().await?` decodes one row at a time as bytes
   arrive, so the 10,000 rows are never materialized into a `Vec`.
6. **Aggregate into typed results.** `fetch_all::<SiteStats>()` collects the five
   grouped rows into a `Vec` of a `Row + Deserialize` struct.
7. **Handle a server error.** The failing query returns `clickhouse::error::Error`;
   the server exception arrives as the `BadResponse(String)` variant and the code is
   parsed out of its `Code: 60, ...` prefix.

## Notes

- **`param` vs `bind`.** The crate has two substitution mechanisms. `Query::param(name, value)`
  sends ClickHouse server-side query parameters (`{name:Type}`) — this is what step 4 uses.
  `Query::bind(value)` fills `?` placeholders by escaping and interpolating **client-side**
  before the SQL is sent; it is used here only for `sql::Identifier`, since table names
  cannot be server-side parameters.
- **No structured error code.** `clickhouse::error::Error` has no field for the ClickHouse
  error code. Server exceptions surface as `Error::BadResponse(String)` holding the raw
  `Code: 60. DB::Exception: ...` text, so the code has to be parsed from the message.
- **`Map` is a `Vec` of pairs.** `Map(K, V)` is wire-compatible with `Array(Tuple(K, V))`,
  so it maps to `Vec<(K, V)>` (or any `IntoIterator` of pairs). There is no direct
  `HashMap` mapping, and round-tripping through a `HashMap` would lose the server's order.
- **`LowCardinality(T)` is transparent**; `device_id` and `site` are plain `String` fields.
- **Type coverage.** `Variant` and `Dynamic` need enum/`Option` shims and `JSON` needs
  type hints; none are used here. Schema validation is on by default (that is why the
  client uses `RowBinaryWithNamesAndTypes`); `Client::with_validation(false)` trades it
  for a little throughput.

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
