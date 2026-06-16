# Convert Parquet to NDJSON with clickhouse-local

Runnable companion to
[How to convert Parquet to NDJSON](https://clickhouse.com/resources/engineering/convert-parquet-to-ndjson).

One line, no server, no upload. The Parquet schema is read from the file footer
and types carry over into NDJSON (one JSON object per line).

```bash
./generate.sh   # writes events.parquet (20 rows) + events_large.parquet (3M rows)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.parquet') INTO OUTFILE 'events.ndjson' TRUNCATE FORMAT JSONEachRow"
```

Covered in `run.sh`: the conversion, footer-driven schema, boolean handling
(UInt8 vs `Bool`), projecting/filtering during conversion, compressed
`.ndjson.gz` output, and a best-of-3 throughput number on the 3M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? See `run.py` / `run.ipynb` for the same conversion with chDB
(`pip install chdb`).
