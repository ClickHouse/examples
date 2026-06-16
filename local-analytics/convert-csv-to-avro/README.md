# Convert CSV to Avro with clickhouse-local

Runnable companion to
[How to convert CSV to Avro](https://clickhouse.com/resources/engineering/convert-csv-to-avro).

One command. Schema is derived from the column types inferred from the CSV, no
upload, no server.

```bash
./generate.sh   # writes events.csv (20 rows) + events_large.csv (~120 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.csv') INTO OUTFILE 'events.avro' FORMAT Avro"
```

Covered in `run.sh`: the conversion, the inferred CSV schema, the Avro schema
carried into the file (read back and read from the embedded header JSON),
pinning column types so the Avro schema has no null unions, the compression
codec setting, and a best-of-3 conversion throughput number on the ~120 MB file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? `run.py` / `run.ipynb` do the same conversion with chDB
(`import chdb`). Requirements: `pip install chdb`.
