# Convert Avro to JSON with clickhouse-local

Runnable companion to
[How to convert Avro to JSON](https://clickhouse.com/resources/engineering/convert-avro-to-json).

Convert an Avro file to JSON with one SQL command — schema read from the Avro
file itself, no upload, no server.

```bash
./generate.sh   # writes events.avro (20 rows) and events_large.avro (3,000,000 rows)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.avro') INTO OUTFILE 'events.jsonl' FORMAT JSONEachRow"
```

Covered in `run.sh`: Avro -> JSON Lines, the embedded-schema `DESCRIBE`, the
DateTime-as-epoch gotcha and the `::DateTime` fix, single JSON array output,
filtering during the conversion, gzipped `.jsonl.gz` output, and a best-of-3
perf number on the 3,000,000-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? `run.py` and `run.ipynb` do the same conversion with chDB
(`pip install chdb`).
