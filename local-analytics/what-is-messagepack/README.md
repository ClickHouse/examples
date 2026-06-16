# What is MessagePack?

Runnable companion to the article
[What is MessagePack?](https://clickhouse.com/resources/engineering/what-is-messagepack).

Generates a small MessagePack file locally with `clickhouse local`, then reads it
back. MessagePack carries no schema, so the read requires an explicit column
structure — the example proves both the success path and the error you get without it.

## Run it

```bash
./generate.sh   # writes data/events.msgpack (20 rows) + a 2M-row file + a JSONL twin
./run.sh        # reads the file, shows the no-schema gotcha, compares size vs JSON
```

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`. `xxd` for the byte dump.

Override row counts for a fast verifier run:

```bash
SMALL_ROWS=20 LARGE_ROWS=200000 ./generate.sh
```

## What's in the file

Synthetic event data: `id`, `country`, `device`, `event_type`, `revenue`, `quantity`.
The small file is the one the article reads; the 2M-row file backs the perf number.

## Notes on reproducibility

The structure, byte layout, and size figures are stable across runs. The `revenue`
column uses `randUniform`, so the `sum(revenue)` totals vary slightly run-to-run;
`expected_output.txt` is a real capture from one run.

Prefer Python? See [Read a MessagePack file in Python](https://clickhouse.com/resources/engineering/read-messagepack-file-python).
