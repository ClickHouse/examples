# Client tour specification

Every implementation in this directory runs the same seven steps against the same
ClickHouse Cloud service and prints the same output. This file is the contract.
`expected-output.txt` is the reference output; `scripts/verify.sh` diffs each
implementation against it.

The domain is device telemetry: sensor readings from fifty devices across five
sites. The dataset is generated in code from the row index, so no PRNG, no
download, and no data files are needed, and every language produces identical rows.

## Connection

Read these environment variables. Fail with a clear message if any is missing.

| Variable | Meaning |
| --- | --- |
| `CLICKHOUSE_HOST` | Cloud hostname, e.g. `abc123.eu-west-1.aws.clickhouse.cloud` |
| `CLICKHOUSE_HTTPS_PORT` | HTTPS port, `8443` |
| `CLICKHOUSE_NATIVE_PORT` | Native TCP over TLS port, `9440` |
| `CLICKHOUSE_USER` | Application user, `client_tour_app` |
| `CLICKHOUSE_PASSWORD` | Application user password |
| `CLICKHOUSE_DATABASE` | `client_tour` |

Always connect with TLS. HTTP-based clients use `CLICKHOUSE_HTTPS_PORT`; native
protocol clients (Go native API, C++) use `CLICKHOUSE_NATIVE_PORT`. Never print
the password.

Each implementation owns one table, `client_tour.readings_<lang>`, where `<lang>`
is the implementation's directory name with hyphens replaced by underscores:
`dotnet`, `java_client`, `java_jdbc`, `rust`, `go`, `cpp`, `python`, `nodejs`.
Separate tables let implementations run concurrently.

## Steps and output

Print exactly the lines below to stdout, in order, one step per line except step 6.
Anything else (debug, progress) goes to stderr. `<lang>` and the server version are
the only values that differ between implementations.

### 1. Connect and ping

Open the client, run `SELECT version()`, print:

```
1 connect: ok, server version <version>
```

### 2. Create the table

Run `DROP TABLE IF EXISTS client_tour.readings_<lang>` then:

```sql
CREATE TABLE client_tour.readings_<lang>
(
    reading_id   UUID,
    recorded_at  DateTime64(3, 'UTC'),
    device_id    LowCardinality(String),
    site         LowCardinality(String),
    temp_c       Float64,
    humidity_pct Nullable(Float64),
    battery_pct  UInt8,
    tags         Array(String),
    attributes   Map(String, String)
)
ENGINE = MergeTree
ORDER BY (site, device_id, recorded_at)
```

Print:

```
2 create table: ok
```

### 3. Insert 10,000 typed rows in 10 batches

Generate rows for `i = 0 .. 9999` (integer arithmetic, then a single division for
the floats, so every language produces bit-identical doubles):

| Column | Value |
| --- | --- |
| `reading_id` | UUID string `00000000-0000-4000-8000-` followed by `i` as 12 lowercase hex digits, zero padded |
| `recorded_at` | `2026-01-01T00:00:00.000Z` plus `i * 1000 + (i * 37) % 1000` milliseconds |
| `device_id` | `device-` followed by `i % 50` as two digits, zero padded (`device-00` .. `device-49`) |
| `site` | `["amsterdam", "berlin", "london", "madrid", "paris"][(i % 50) % 5]` |
| `temp_c` | `15.0 + ((i * 7919) % 1997) / 100.0` |
| `humidity_pct` | `NULL` when `i % 10 == 0`, else `30.0 + ((i * 104729) % 6000) / 100.0` |
| `battery_pct` | `100 - (i % 101)` |
| `tags` | `i % 3 == 0` → `["calibrated"]`; `i % 3 == 1` → `["calibrated", "outdoor"]`; else `[]` |
| `attributes` | `{"firmware": "1." + (i % 4), "model": i % 2 == 0 ? "tx-100" : "tx-200"}` |

Use 64-bit integers for `i * 104729` (max 1,047,185,271, fits in 32 bits, but do
not rely on it). Map values are strings: `1.0`, `1.1`, `1.2`, `1.3`. The modulus
1997 is deliberate: with 2000 the per-site mean temperatures land exactly on
`.xx5` boundaries, and `round(avg(Float64), 2)` then depends on the server's
summation order across parts and threads. 1997 keeps every mean at least 0.06 of
a cent away from a boundary, so step 6 is stable regardless of part layout.

Insert using the client's typed or binary insert path (POCO, POJO, serde struct,
Go struct or column append, C++ blocks, Python columnar or row lists, Node.js JSONEachRow rows), in 10 batches of 1,000 rows. Do not build SQL
strings with literal values. Print:

```
3 insert: 10000 rows in 10 batches
```

### 4. Parameterized query

Count readings for one device above a threshold, binding both values as parameters
rather than string formatting. Use server-side parameters (`{device:String}`,
`{min_temp:Float64}`) where the client supports them; otherwise use the client's
own binding mechanism and say so in the implementation's README.

```sql
SELECT count() FROM client_tour.readings_<lang>
WHERE device_id = {device:String} AND temp_c > {min_temp:Float64}
```

with `device = 'device-07'` and `min_temp = 30.0`. Print:

```
4 parameterized query: 48 readings for device-07 above 30.0 C
```

### 5. Stream all rows back

Select all rows (`SELECT * ... ORDER BY recorded_at`) through the client's
streaming or cursor API so that rows are processed as they arrive rather than
loaded into one list. Deserialize every column into native types (UUID, timestamp,
nullable float, array, map). While iterating, compute client-side: the row count,
the sum of `battery_pct`, the number of rows where `humidity_pct` is null, and the
total number of tags. Print:

```
5 stream: 10000 rows, battery total 500050, humidity null in 1000 rows, 10000 tags
```

### 6. Aggregate into typed results

```sql
SELECT site, count() AS readings,
       round(avg(temp_c), 2) AS avg_temp_c,
       round(max(temp_c), 2) AS max_temp_c
FROM client_tour.readings_<lang>
GROUP BY site ORDER BY site
```

Map each result row to a typed record (struct, class, or dataclass), then print a
header line and one line per site. Floats are formatted with exactly two decimals.
Fields are separated by a single space.

```
6 aggregate: site readings avg_temp_c max_temp_c
6 aggregate: amsterdam 2000 24.98 34.96
6 aggregate: berlin 2000 24.99 34.96
6 aggregate: london 2000 24.99 34.96
6 aggregate: madrid 2000 24.99 34.96
6 aggregate: paris 2000 24.99 34.96
```

### 7. Handle a server error

Run `SELECT count() FROM client_tour.no_such_table_<lang>`, catch the client's
exception type, and extract the ClickHouse error code (60, `UNKNOWN_TABLE`) from
the exception's code field, or by parsing `Code: 60` from the message if the client
exposes no field. Print:

```
7 error: server error code 60
```

Then close the client and exit 0. Any other failure exits non-zero.

## Per-language directory contents

```
<lang>/
  README.md     what this client is, package coordinates, how to run, notes on
                anything the client does differently from the spec (e.g. parameter
                binding style), and the exact expected output
  run.sh        builds if needed and runs the program; assumes the env vars are
                already exported; exits with the program's exit code
  <source>      idiomatic code for that language, small enough to read top to bottom
```

`run.sh` must be runnable from any working directory (`cd "$(dirname "$0")"` first).
Pin the client library to a specific current version. Use the client's recommended,
current API (Java Client V2 not V1, `ClickHouse.Driver` not `ClickHouse.Client`,
`clickhouse-go/v2` native API, `clickhouse-connect`, `@clickhouse/client`).

## Rules

- No secrets in code, logs, or READMEs. Credentials come only from the environment.
- Do not commit build output, lockfiles for compiled languages are fine.
- Keep it a tour of the client, not a framework demo: no web servers, no ORMs.
- Comment the code where the client's behaviour is non-obvious, not where it isn't.
