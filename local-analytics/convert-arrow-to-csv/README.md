# Convert Arrow to CSV with clickhouse-local

Runnable companion to
[How to convert Arrow to CSV](https://clickhouse.com/resources/engineering/convert-arrow-to-csv).

Convert an Arrow (Arrow IPC / Feather) file to CSV with one command. The schema
is read from the Arrow file itself, so types carry over and you supply nothing.

```bash
./generate.sh   # writes events.arrow (20 rows, incl. a nested Array column) + events_large.arrow (~63 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.arrow') INTO OUTFILE 'events.csv' TRUNCATE FORMAT CSVWithNames"
```

Covered in `run.sh`: one-line conversion, the embedded-schema `DESCRIBE`, the
nested `Array` -> flat CSV string gotcha, header vs no-header (`CSVWithNames` vs
`CSV`), transforming during conversion, and a best-of-3 perf number on the 3M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? See the chDB version in `run.py` / `run.ipynb` (`import chdb`).
