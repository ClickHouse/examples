# What is a BSON file?

Runnable companion to the article
[What is a BSON file?](https://clickhouse.com/resources/engineering/what-is-bson).

BSON is Binary JSON: MongoDB's typed, length-prefixed binary document format.
This example writes a small BSON file with `clickhouse local`, reads it back
(schema inferred from the embedded types), and shows the raw bytes so you can
see the length prefix and per-field type tags.

## Run it

```bash
./generate.sh   # writes data/users.bson (5 rows) and data/events.bson (1.5M rows)
./run.sh        # reads + describes the BSON, shows the bytes, aggregates
```

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`. Step 3 uses `xxd` (preinstalled on macOS/Linux).

Override row counts for a fast verify:

```bash
SMALL_ROWS=5 LARGE_ROWS=200000 ./generate.sh
```

## What's in the files

- `users.bson` — a handful of typed user documents: `user_id` (int64), `name`,
  `country` (strings), `signup_time` (datetime), `balance` (double), `active` (bool).
- `events.bson` — 1.5M event rows for an honest read-throughput number.

## Note on round-trips

BSON has its own type set. When `clickhouse local` reads the file back it infers
`signup_time` as `Int64` (epoch seconds) and the boolean `active` as `Int32` —
both faithful to the bytes on disk. Cast them on read if you want richer types:
`SELECT toDateTime(signup_time), active::Bool FROM file('data/users.bson', BSONEachRow)`.
