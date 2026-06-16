# Convert NPY to Parquet with clickhouse-local

Runnable companion to
[How to convert NPY to Parquet](https://clickhouse.com/resources/engineering/convert-npy-to-parquet).

A `.npy` file holds one numeric array. `clickhouse-local` reads it as a single
column named `array`, infers the dtype, and writes typed Parquet in one line —
no upload, no server, no Python.

```bash
./generate.sh   # writes readings.npy (10 floats) and embeddings.npy (2,000,000 x 16, ~128 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('readings.npy') INTO OUTFILE 'readings.parquet' FORMAT Parquet"
```

Covered in `run.sh`: the always-named `array` column and how to rename it,
1D scalar vs 2D matrix `.npy`, keeping row vectors as an `Array` column or
expanding them into named scalar columns, the NPY-vs-Parquet size drop, and a
best-of-3 conversion time on the 2,000,000-row matrix.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? `run.py` and `run.ipynb` do the same conversion with chDB
(`pip install chdb`).
