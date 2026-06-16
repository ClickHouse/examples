# What is Protobuf?

Runnable companion to the article
[What is Protobuf?](https://clickhouse.com/resources/engineering/what-is-protobuf).

Protocol Buffers (Protobuf) is a schema-first binary serialization format. The
message layout lives in a separate `.proto` file, not in the data, so you must
supply that schema to read or write it. This example uses `clickhouse local` to
write a `.bin` from `events.proto` and read it straight back as a queryable table.

## Run it

```bash
./generate.sh   # writes data/events.bin (20 rows) + data/events_large.bin (3,000,000 rows)
./run.sh        # reads the binary with the .proto schema, DESCRIBEs it, queries it
```

Override row counts for a fast verify:

```bash
SMALL_ROWS=20 LARGE_ROWS=200000 ./generate.sh
```

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

## Files

- `events.proto` — the schema. `message Event` = one row; field numbers are the wire identity.
- `generate.sh` — synthesises Protobuf data with `FORMAT Protobuf` + `SETTINGS format_schema`.
- `run.sh` — the exact commands from the article.

## The schema requirement

Protobuf carries no embedded schema. Reading without `format_schema` fails on
purpose (step 1 of `run.sh`). Every read passes
`SETTINGS format_schema = 'events.proto:Event'`. The `messageName` after the colon
picks which `message` in the `.proto` to use.

## Reproducibility

Structure (columns, types, byte framing) is deterministic. The `revenue` column
uses `randUniform`, so the `sum(revenue)` figures in step 4 vary run-to-run;
`expected_output.txt` is a real capture from one run.
