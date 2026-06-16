# Convert CSV to TSV with clickhouse-local

Runnable companion to
[How to convert CSV to TSV](https://clickhouse.com/resources/engineering/convert-csv-to-tsv).

Convert a CSV to tab-separated values in one command — header kept, types
carried over, no upload and no import step.

```bash
./generate.sh   # writes orders.csv, notes.csv, orders_large.csv (~126 MB) into data/
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('orders.csv') INTO OUTFILE 'orders.tsv' TRUNCATE FORMAT TSVWithNames"
```

Covered in `run.sh`: CSV -> TSV with the header kept (`TSVWithNames`) vs dropped
(`TSV`), how an embedded comma stays literal while an embedded tab is escaped to
`\t` (lossless round-trip), and a best-of-3 conversion-throughput number on the
~3M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? `run.py` / `run.ipynb` do the same conversion with chDB
(`pip install chdb`).
