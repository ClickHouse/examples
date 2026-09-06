# Java client tour: JDBC driver (clickhouse-jdbc)

`com.clickhouse:clickhouse-jdbc` is ClickHouse's official `java.sql` driver. The
0.10.x line (JDBC "V2") is built on top of [Client V2](../java-client/README.md):
every query and insert goes over HTTP(S), and the driver formats each bound
`?` value into the outgoing SQL text using the same encoders Client V2 uses for
literals, rather than sending a separate binary parameter frame. Coordinates
are `com.clickhouse:clickhouse-jdbc:0.10.0`, classifier `all` (bundles Apache
HttpClient 5 and friends into one jar). The driver targets Java 17+; this
example builds with `--release 17` on JDK 21. Reach for plain JDBC when a
framework, connection pool, or ORM expects a `java.sql.Driver` and you don't
control the data-access layer; reach for [Client V2](../java-client/README.md)
directly when you do, since it gives you RowBinary inserts/reads and server-side
named parameters without the JDBC abstraction in between.

## Prerequisites

- JDK 17+ (this repo uses JDK 21 via Homebrew) and Maven 3.9+.
- A provisioned ClickHouse Cloud service and a `.env` file, as set up by the
  parent [`../README.md`](../README.md).

You need a ClickHouse Cloud account. [Sign up at clickhouse.com/cloud](https://clickhouse.com/cloud) to start a free trial with $300 in credits.

## Run

```sh
set -a; source ../.env; set +a
./run.sh
```

## What the code does

1. **Connect and ping** — `DriverManager.getConnection(url, props)` opens the
   connection (`jdbc:clickhouse:https://host:port/database?ssl=true`); a plain
   `Statement` runs `SELECT version()`.
2. **Create the table** — two `Statement.execute()` calls (`DROP TABLE IF
   EXISTS`, then `CREATE TABLE`); JDBC DDL has no typed result to read.
3. **Insert 10,000 rows in 10 batches** — one `PreparedStatement` with `?`
   placeholders for all nine columns; `addBatch()` per row, `executeBatch()`
   every 1,000 rows. `setObject` takes a `UUID` for `reading_id`, an `Instant`
   for `recorded_at`, a plain `String[]` for `tags`, and a `java.util.Map` for
   `attributes` — the driver recognizes each type and renders it into the
   generated `INSERT ... VALUES` text; a `null` `Double` for `humidity_pct`
   renders as SQL `NULL`.
4. **Parameterized query** — a second `PreparedStatement` binds `device_id`
   and `temp_c` as `?` placeholders (see Notes: no server-side named
   parameters in JDBC).
5. **Stream all rows back** — `Statement.setFetchSize(1000)` before
   `executeQuery`, then a `while (rs.next())` loop. Each row is read into a
   `Reading` record via `getObject(..., UUID.class)`, `getTimestamp`,
   `getArray(...).getArray()`, and a direct `getObject` cast to `Map` — no
   column needs a manual null check beyond `humidity_pct`, which JDBC already
   returns as a nullable boxed `Double`.
6. **Aggregate into typed results** — the `GROUP BY site` query is run through
   a `Statement`, and each row is mapped into a `SiteAggregate` record before
   printing.
7. **Handle a server error** — `Statement.executeQuery` against the missing
   table throws `SQLException`; `getErrorCode()` returns the ClickHouse error
   code (60) directly, because this driver copies `ServerException.getCode()`
   into the `SQLException` vendor code field. A regex fallback that parses
   `Code: 60` out of the message is included in case a future driver version
   stops populating that field.

## Notes

- **No named parameters.** The JDBC spec has no concept of `{name:Type}`
  server-side parameters, and this driver doesn't add one — step 4 uses
  standard `?` placeholders instead, unlike the Client V2 tour in
  [`../java-client`](../java-client/README.md).
- **Parameter binding is client-side text substitution, not a wire-protocol
  bind.** Each `?` value is escaped and formatted into the SQL string before
  it is sent (see `PreparedStatementImpl.encodeObject` in the driver source);
  there is no prepare/execute round trip and no reusable compiled statement on
  the server. It is still injection-safe, just not a "real" bound parameter in
  the native-protocol sense.
- **No transactions.** ClickHouse has no multi-statement ACID transactions,
  and this driver's `Connection` does not support them; `setAutoCommit(false)`
  and friends are not used here.
- **Arrays and maps bind directly.** `setObject` accepts a plain `String[]`
  for `Array(String)` and a `java.util.Map` for `Map(String, String)` — no
  `Connection.createArrayOf(...)` or wrapper type is required, and reading
  them back needs only `ResultSet.getArray(...).getArray()` and a cast on
  `getObject(...)`.

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
