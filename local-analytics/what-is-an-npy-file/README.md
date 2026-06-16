# What is an .npy file?

Runnable companion to the article
[What is an .npy file?](https://clickhouse.com/resources/engineering/what-is-an-npy-file).

Generates small demo `.npy` files (NumPy's binary array format) locally, then uses
`clickhouse local` to crack open the header (magic string, version, dtype, shape) and
to read the array back as a queryable table.

## Run it

```bash
./generate.sh   # writes data/readings.npy (20 Float64) + data/readings_large.npy (3,000,000)
./run.sh        # inspects the header, then DESCRIBEs and queries the array
```

Override row counts for a fast verify:

```bash
SMALL_ROWS=8 LARGE_ROWS=100000 ./generate.sh
```

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

## What's in the files

A `.npy` file holds exactly one numeric array. `readings.npy` is a 1-D array of 20
`Float64` "temperature" readings; `readings_large.npy` is the same shape with 3,000,000
elements. ClickHouse reads them as a single-column table whose column is named `array`.

## Notes on reproducibility

The values are deterministic (`sin`-based), so the header (`'<f8'`, shape) and the
aggregates in `expected_output.txt` are stable across runs.
