# Java client tour: Client V2 (client-v2)

[Client V2](https://clickhouse.com/docs/integrations/language-clients/java/client) is the
recommended ClickHouse client for Java. It talks HTTP(S) and speaks RowBinary on the wire,
so inserts and reads are binary rather than SQL text. It replaces the V1 `clickhouse-client`
API (deprecated) and sits underneath `clickhouse-jdbc` v2, which is the right choice only
when a framework demands a `java.sql.Driver`; new code should use Client V2 directly.
Coordinates are `com.clickhouse:client-v2`, pinned here to `0.10.0`. The client requires
JDK 8+; this example compiles to Java 17 bytecode (`maven.compiler.release` 17) and was
tested on JDK 21.

## Prerequisites

- JDK 17 or newer and Maven 3.9+.
- A provisioned ClickHouse Cloud service and a `.env` file, both created by the steps in
  the [parent README](../README.md).
- You need a ClickHouse Cloud account. [Sign up at clickhouse.com/cloud](https://clickhouse.com/cloud) to start a free trial with $300 in credits.

## Run

```sh
set -a; source ../.env; set +a
./run.sh
```

## What the code does

[`ClientTour.java`](./src/main/java/com/clickhouse/examples/clienttour/ClientTour.java) is
the whole tour; [`Reading.java`](./src/main/java/com/clickhouse/examples/clienttour/Reading.java)
is the insert POJO and [`SiteStats.java`](./src/main/java/com/clickhouse/examples/clienttour/SiteStats.java)
the aggregate record.

1. **Connect and ping.** `new Client.Builder().addEndpoint("https://host:8443")` with
   `setUsername`/`setPassword`/`setDefaultDatabase`. HTTPS endpoints default to
   `SSLMode.STRICT`, so TLS with full certificate verification needs no extra configuration.
   `queryAll("SELECT version()")` returns a `List<GenericRecord>`.
2. **Create the table.** `client.execute(sql)` for DDL: it returns a `CommandResponse`
   future with server metrics and no result set.
3. **Insert 10,000 rows in 10 batches.** `client.register(Reading.class, client.getTableSchema(TABLE))`
   compiles a RowBinary serializer for the POJO against the live table schema, then each
   `client.insert(TABLE, List<Reading>)` streams one batch as binary rows. No SQL is built.
4. **Parameterized query.** Server-side parameters: the SQL keeps `{device:String}` and
   `{min_temp:Float64}` and a `Map<String, Object>` is passed to
   `queryAll(sql, params)`, which sends them as `param_*` HTTP query arguments.
5. **Stream all rows back.** `client.query(sql)` gives a `QueryResponse` holding an open
   stream; `client.newBinaryFormatReader(response)` wraps it in a `ClickHouseBinaryFormatReader`
   that decodes one row at a time from RowBinaryWithNamesAndTypes. Typed getters produce
   `UUID`, `ZonedDateTime`, `List<String>` and `short` directly; `readValue()` returns the
   nullable `Double` and the `Map<String, String>`.
6. **Aggregate into typed results.** `queryAll` again, mapping each `GenericRecord` into the
   `SiteStats` record with `getString`/`getLong`/`getDouble`.
7. **Handle a server error.** `com.clickhouse.client.api.ServerException` exposes the
   ClickHouse error code through `getCode()`, so there is nothing to parse out of the message.

## Notes

- The client runs operations in the calling thread by default (`useAsyncRequests(false)`),
  so a `ServerException` is thrown straight out of `query()`/`execute()` rather than wrapped
  in an `ExecutionException`. The methods still return `CompletableFuture`, so `.get()` is
  needed to reach the response.
- `queryAll()` is the exception: it catches everything and rethrows a `ClientException` with
  the `ServerException` as its cause. Step 7 therefore uses `query()` so the
  `ServerException` surfaces directly.
- The client logs through SLF4J. This example depends on `slf4j-nop` so nothing is written
  to stdout; swap in `slf4j-simple` or Logback to see the client's own logging.
- Column-to-method matching strips `get`/`set` and underscores and compares
  case-insensitively, so `reading_id` binds to `getReadingId()`. `Reading` is write-only and
  has no setters, which makes the client log one warning per column at registration time
  (silenced here by `slf4j-nop`).
- `mvn package` builds a shaded runnable jar at `target/client-tour.jar`.

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
