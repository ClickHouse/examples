# Read a .npy (NumPy) file with clickhouse-local

Runnable companion to
[How to read a .npy file with SQL](https://clickhouse.com/resources/engineering/read-npy-file).

An `.npy` file holds one numeric NumPy array. Point `clickhouse local` at it with
the `Npy` format and query it with SQL — no Python, no import step.

```bash
./generate.sh   # writes revenue.npy, quantity.npy (10 values each), scores_large.npy (3M Float64)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner (the format name is required for `.npy`):

```bash
clickhouse local -q "SELECT * FROM file('revenue.npy', Npy) LIMIT 5"
```

Covered in `run.sh`: reading the single `array` column, `DESCRIBE` for the dtype,
renaming the column with an explicit structure, aggregation, zipping two `.npy`
arrays into rows by position, and a best-of-3 perf number on a 3,000,000-value file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh`
then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? See the chDB version: [read a .npy file in Python](https://clickhouse.com/resources/engineering/read-npy-file-python).
