# Convert Avro to CSV with clickhouse-local

Runnable companion to
[Convert Avro to CSV](https://clickhouse.com/resources/engineering/convert-avro-to-csv).

One line, no upload, no server. Avro carries its own schema, so types come along for free.

```bash
./generate.sh   # writes events.avro (20 rows, nested Tuple + Array), events_large.avro (~81 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.avro') INTO OUTFILE 'events.csv' FORMAT CSVWithNames"
```

Covered in `run.sh`: the one-line conversion, what the Avro schema carries (a raw
int timestamp, a named Tuple, an Array), flattening nested fields into clean flat
columns, and a best-of-3 perf number on the 3M-row file.

Prefer Python? `run.py` / `run.ipynb` do the same conversion with chDB
(`import chdb; chdb.query(... INTO OUTFILE ... FORMAT CSVWithNames)`).

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`. For the Python path: `pip install chdb`.
