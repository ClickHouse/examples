# Convert CSV to ORC with clickhouse-local

Runnable companion to
[How to convert CSV to ORC](https://clickhouse.com/resources/engineering/convert-csv-to-orc).

Convert a CSV to columnar ORC with one command. No upload, no server — the schema
is inferred from the CSV and the types are carried into ORC.

```bash
./generate.sh   # writes events.csv (20 rows) and events_large.csv (~123 MB, 3M rows)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.csv') INTO OUTFILE 'events.orc' TRUNCATE FORMAT ORC"
```

Covered in `run.sh`: the one-line conversion, schema/type carry-over (note ORC stores
signed ints and `Date32`), reading the ORC back, pinning types on conversion, the ORC
compression codecs, and a best-of-3 conversion-throughput number on the 3M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? `run.py` / `run.ipynb` do the same conversion in-process with
[chDB](https://clickhouse.com/resources/engineering/what-is-chdb) (`pip install chdb`).
