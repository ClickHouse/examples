# Convert JSON to TSV with clickhouse-local

Runnable companion to
[How to convert JSON to TSV](https://clickhouse.com/resources/engineering/convert-json-to-tsv).

Convert a JSON file to a tab-separated file with one command — schema
auto-inferred, types preserved, no upload and no server.

```bash
./generate.sh   # writes events.jsonl (8 rows, nested user object), events_large.jsonl (~137 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.jsonl') INTO OUTFILE 'events.tsv' TRUNCATE FORMAT TSVWithNames"
```

The catch: a nested JSON object (`user`) lands in a single TSV cell as a
serialized tuple. Flatten it first by selecting `user.id`, `user.plan` as
their own columns. `run.sh` shows both the naive and the flattened conversion,
plus a best-of-3 perf number on the 1M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? See `run.py` / `run.ipynb` for the chDB version (`pip install chdb`).
