# Convert Parquet to ORC with clickhouse-local

Runnable companion to
[How to convert Parquet to ORC](https://clickhouse.com/resources/engineering/convert-parquet-to-orc).

Columnar to columnar, no upload and no server. Schema is read from the Parquet
footer; types carry into ORC.

```bash
./generate.sh   # writes data/events.parquet (20 rows) + events_large.parquet (3,000,000 rows)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.parquet') INTO OUTFILE 'events.orc' TRUNCATE FORMAT ORC"
```

Covered in `run.sh`: the one-line conversion, source vs. result schema, a
correctness check that both files give the same aggregate, choosing the ORC
compression codec, and a best-of-3 conversion time on the 3M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? `run.py` and `run.ipynb` do the same conversion in-process with
chDB (`pip install chdb`).
