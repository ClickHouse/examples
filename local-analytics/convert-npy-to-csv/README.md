# Convert NPY to CSV with clickhouse-local

Runnable companion to
[How to convert NPY to CSV](https://clickhouse.com/resources/engineering/convert-npy-to-csv).

Convert a NumPy `.npy` array to CSV with one command — dtype is read from the
`.npy` header, no upload, no Python required.

```bash
./generate.sh   # writes signal.npy (1D), matrix.npy (2D), signal_large.npy (3M)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('signal.npy') INTO OUTFILE 'signal.csv' FORMAT CSVWithNames"
```

Covered in `run.sh`: 1D `.npy` -> CSV, the inferred dtype, the 2D-array gotcha
(a 2D `.npy` reads as one `Array` column), expanding that array into real CSV
columns, and a best-of-3 perf number on a 3,000,000-element file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? `run.py` / `run.ipynb` do the same conversion with chDB (`pip install chdb`).
