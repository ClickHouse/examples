# Convert Parquet to TSV with clickhouse-local

Runnable companion to
[How to convert Parquet to TSV](https://clickhouse.com/resources/engineering/convert-parquet-to-tsv).

Convert a Parquet file to tab-separated values with one command — types come
from the Parquet footer, no upload, no server.

```bash
./generate.sh   # writes events.parquet (20 rows) + events_large.parquet (3M rows)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.parquet') INTO OUTFILE 'events.tsv' TRUNCATE FORMAT TSV"
```

Covered in `run.sh`: the conversion, the inferred Parquet schema, `TSVWithNames`
to keep column names, reading the TSV back (the nested `tags` array round-trips),
flattening an array to one row per element, and a best-of-3 conversion-throughput
number on the 3M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? `run.py` and `run.ipynb` do the same conversion with chDB
(`pip install chdb`).
