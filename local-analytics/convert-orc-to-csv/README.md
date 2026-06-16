# Convert ORC to CSV with clickhouse-local

Runnable companion to
[How to convert ORC to CSV](https://clickhouse.com/resources/engineering/convert-orc-to-csv).

Convert an ORC file to CSV with one command — schema read from the ORC footer,
no server, no upload, streams files larger than RAM.

```bash
./generate.sh   # writes events.orc (20 rows) + events_large.orc (3M rows)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.orc') INTO OUTFILE 'events.csv' FORMAT CSVWithNames"
```

Covered in `run.sh`: the one-line conversion, the schema ClickHouse infers from
the ORC footer, the `Map`-column gotcha (flatten nested columns so the CSV stays
tabular), tidying the timestamp / keeping the map as a JSON string, a row-count
round-trip check, and a best-of-3 conversion-throughput number on the 3M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? See the chDB version in `run.py` / `run.ipynb` (needs `pip install chdb`).
