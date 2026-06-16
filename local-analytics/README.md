# Local analytics with ClickHouse

Runnable examples for analysing files and data sources on your laptop with
[`clickhouse-local`](https://clickhouse.com/docs/operations/utilities/clickhouse-local)
(the command line) and [chDB](https://clickhouse.com/docs/chdb) (in-process ClickHouse for Python) —
no server, no import step.

Each subfolder is a self-contained, runnable companion to a how-to article on clickhouse.com.

## Folder convention

Every example folder follows the same shape:

```
local-analytics/<surface>-<topic>/
├── README.md        # code-first, terse; links to the companion article
├── generate.sh      # creates the sample data locally (no large binaries committed)
├── run.sh           # the exact commands from the article (CLI examples)  -- or --
├── run.ipynb / run.py   # the exact code from the article (chDB / Python examples)
└── expected_output.txt  # what you should see, so the example is self-verifying
```

- `<surface>` is `clickhouse-local` or `chdb`.
- Sample data is **generated locally** by `generate.sh` (using `clickhouse local` itself, where possible) so nothing large is committed to git.
- `run.sh` / `run.ipynb` reproduce exactly the commands shown in the article.
- The article is canonical for prose; this folder is canonical for code. They link to each other.

## Index

| Folder | Companion article | Surface |
|---|---|---|
| [`clickhouse-local-intro`](./clickhouse-local-intro) | What is clickhouse-local? | clickhouse-local |
| [`clickhouse-local-parquet`](./clickhouse-local-parquet) | How to query a Parquet file from the command line | clickhouse-local |
| [`clickhouse-local-csv`](./clickhouse-local-csv) | How to run SQL on a CSV file | clickhouse-local |
| [`clickhouse-local-logs`](./clickhouse-local-logs) | How to analyze log files with SQL | clickhouse-local |
| [`what-is-parquet-file`](./what-is-parquet-file) | What is a Parquet file? | clickhouse-local |
| [`chdb-parquet`](./chdb-parquet) | How to read a Parquet file in Python | chDB |
| [`chdb-json`](./chdb-json) | How to read a JSON file in Python | chDB |

### File-format reads — clickhouse-local (CLI)

| Folder | Companion article | Surface |
|---|---|---|
| [`clickhouse-local-avro`](./clickhouse-local-avro) | How to read an Avro file | clickhouse-local |
| [`clickhouse-local-avro-confluent`](./clickhouse-local-avro-confluent) | Read Avro from a schema registry with clickhouse-local | clickhouse-local |
| [`clickhouse-local-bson`](./clickhouse-local-bson) | How to query a BSON file | clickhouse-local |
| [`clickhouse-local-compressed`](./clickhouse-local-compressed) | How to query a compressed file (gzip, zstd) from the command line | clickhouse-local |
| [`clickhouse-local-custom-delimiter`](./clickhouse-local-custom-delimiter) | How to read a file with a custom delimiter | clickhouse-local |
| [`clickhouse-local-feather`](./clickhouse-local-feather) | How to read a Feather file from the command line | clickhouse-local |
| [`clickhouse-local-form`](./clickhouse-local-form) | Parse url-encoded form data with SQL | clickhouse-local |
| [`clickhouse-local-json`](./clickhouse-local-json) | How to query a JSON file with SQL | clickhouse-local |
| [`clickhouse-local-json-lines`](./clickhouse-local-json-lines) | How to query a JSON Lines file | clickhouse-local |
| [`clickhouse-local-jsonl`](./clickhouse-local-jsonl) | How to run SQL on a JSONL file | clickhouse-local |
| [`clickhouse-local-messagepack`](./clickhouse-local-messagepack) | How to read a MessagePack file | clickhouse-local |
| [`clickhouse-local-mysqldump`](./clickhouse-local-mysqldump) | How to query a mysqldump file without importing | clickhouse-local |
| [`clickhouse-local-native`](./clickhouse-local-native) | How to read a ClickHouse Native format file | clickhouse-local |
| [`clickhouse-local-ndjson`](./clickhouse-local-ndjson) | How to query an NDJSON file with SQL | clickhouse-local |
| [`clickhouse-local-nested-json`](./clickhouse-local-nested-json) | How to query nested JSON with SQL | clickhouse-local |
| [`clickhouse-local-npy`](./clickhouse-local-npy) | How to read a .npy (NumPy) file with SQL | clickhouse-local |
| [`clickhouse-local-orc`](./clickhouse-local-orc) | How to read an ORC file from the command line | clickhouse-local |
| [`clickhouse-local-pipe-delimited`](./clickhouse-local-pipe-delimited) | How to read a pipe-delimited file | clickhouse-local |
| [`clickhouse-local-regexp`](./clickhouse-local-regexp) | How to parse a log file with regex in SQL | clickhouse-local |
| [`clickhouse-local-rowbinary`](./clickhouse-local-rowbinary) | How to read a RowBinary file | clickhouse-local |
| [`clickhouse-local-semicolon`](./clickhouse-local-semicolon) | How to read a semicolon-separated file | clickhouse-local |
| [`clickhouse-local-tsv`](./clickhouse-local-tsv) | How to read a TSV file | clickhouse-local |

### File-format reads — chDB (Python)

| Folder | Companion article | Surface |
|---|---|---|
| [`chdb-arrow`](./chdb-arrow) | How to read an Arrow file in Python (and query it with SQL) | chDB |
| [`chdb-avro`](./chdb-avro) | How to read an Avro file in Python (and query it with SQL) | chDB |
| [`chdb-bson`](./chdb-bson) | How to read a BSON file in Python and query it with SQL | chDB |
| [`chdb-csv`](./chdb-csv) | How to read a CSV file in Python (and query it with SQL) | chDB |
| [`chdb-feather`](./chdb-feather) | How to read a Feather file in Python (and query it with SQL) | chDB |
| [`chdb-flatten-nested-json`](./chdb-flatten-nested-json) | How to flatten nested JSON in Python | chDB |
| [`chdb-jsonl`](./chdb-jsonl) | How to read a JSONL file in Python and query it with SQL | chDB |
| [`chdb-messagepack`](./chdb-messagepack) | How to read a MessagePack file in Python (and query it with SQL) | chDB |
| [`chdb-ndjson`](./chdb-ndjson) | How to read an NDJSON file in Python and query it with SQL | chDB |
| [`chdb-npy`](./chdb-npy) | How to read a .npy file in Python (and query it with SQL) | chDB |
| [`chdb-orc`](./chdb-orc) | How to read an ORC file in Python (and query it with SQL) | chDB |
| [`chdb-tsv`](./chdb-tsv) | How to read a TSV file in Python and query it with SQL | chDB |

### Special read angles

| Folder | Companion article | Surface |
|---|---|---|
| [`chdb-rest-api`](./chdb-rest-api) | How to query an API with SQL in Python | chDB |
| [`clickhouse-local-multiple-files`](./clickhouse-local-multiple-files) | Run SQL across multiple CSV or Parquet files | clickhouse-local |
| [`clickhouse-local-rest-api`](./clickhouse-local-rest-api) | How to query a REST API with SQL | clickhouse-local |

### Format conversions

| Folder | Companion article | Surface |
|---|---|---|
| [`convert-arrow-to-csv`](./convert-arrow-to-csv) | How to convert Arrow to CSV | clickhouse-local |
| [`convert-arrow-to-parquet`](./convert-arrow-to-parquet) | How to convert Arrow to Parquet | clickhouse-local |
| [`convert-avro-to-csv`](./convert-avro-to-csv) | How to convert Avro to CSV | clickhouse-local |
| [`convert-avro-to-json`](./convert-avro-to-json) | How to convert Avro to JSON | clickhouse-local |
| [`convert-avro-to-parquet`](./convert-avro-to-parquet) | How to convert Avro to Parquet | clickhouse-local |
| [`convert-bson-to-csv`](./convert-bson-to-csv) | Convert BSON to CSV | clickhouse-local |
| [`convert-bson-to-json`](./convert-bson-to-json) | How to convert BSON to JSON | clickhouse-local |
| [`convert-csv-to-arrow`](./convert-csv-to-arrow) | How to convert CSV to Arrow | clickhouse-local |
| [`convert-csv-to-avro`](./convert-csv-to-avro) | How to convert CSV to Avro | clickhouse-local |
| [`convert-csv-to-json`](./convert-csv-to-json) | How to convert CSV to JSON | clickhouse-local |
| [`convert-csv-to-jsonl`](./convert-csv-to-jsonl) | How to convert CSV to JSONL | clickhouse-local |
| [`convert-csv-to-ndjson`](./convert-csv-to-ndjson) | How to convert CSV to NDJSON | clickhouse-local |
| [`convert-csv-to-orc`](./convert-csv-to-orc) | How to convert CSV to ORC | clickhouse-local |
| [`convert-csv-to-parquet`](./convert-csv-to-parquet) | How to convert CSV to Parquet | clickhouse-local |
| [`convert-csv-to-tsv`](./convert-csv-to-tsv) | How to convert CSV to TSV | clickhouse-local |
| [`convert-json-to-csv`](./convert-json-to-csv) | How to convert JSON to CSV | clickhouse-local |
| [`convert-json-to-jsonl`](./convert-json-to-jsonl) | How to convert JSON to JSONL | clickhouse-local |
| [`convert-json-to-parquet`](./convert-json-to-parquet) | How to convert JSON to Parquet | clickhouse-local |
| [`convert-json-to-tsv`](./convert-json-to-tsv) | How to convert JSON to TSV | clickhouse-local |
| [`convert-jsonl-to-csv`](./convert-jsonl-to-csv) | How to convert JSONL to CSV | clickhouse-local |
| [`convert-jsonl-to-json`](./convert-jsonl-to-json) | How to convert JSONL to JSON | clickhouse-local |
| [`convert-jsonl-to-parquet`](./convert-jsonl-to-parquet) | How to convert JSONL to Parquet | clickhouse-local |
| [`convert-messagepack-to-csv`](./convert-messagepack-to-csv) | How to convert MessagePack to CSV | clickhouse-local |
| [`convert-messagepack-to-json`](./convert-messagepack-to-json) | How to convert MessagePack to JSON | clickhouse-local |
| [`convert-ndjson-to-csv`](./convert-ndjson-to-csv) | How to convert NDJSON to CSV | clickhouse-local |
| [`convert-ndjson-to-parquet`](./convert-ndjson-to-parquet) | How to convert NDJSON to Parquet | clickhouse-local |
| [`convert-npy-to-csv`](./convert-npy-to-csv) | How to convert NPY to CSV | clickhouse-local |
| [`convert-npy-to-parquet`](./convert-npy-to-parquet) | How to convert NPY to Parquet | clickhouse-local |
| [`convert-orc-to-csv`](./convert-orc-to-csv) | How to convert ORC to CSV | clickhouse-local |
| [`convert-orc-to-json`](./convert-orc-to-json) | How to convert ORC to JSON | clickhouse-local |
| [`convert-orc-to-parquet`](./convert-orc-to-parquet) | How to convert ORC to Parquet | clickhouse-local |
| [`convert-parquet-to-arrow`](./convert-parquet-to-arrow) | How to convert Parquet to Arrow | clickhouse-local |
| [`convert-parquet-to-avro`](./convert-parquet-to-avro) | How to convert Parquet to Avro | clickhouse-local |
| [`convert-parquet-to-csv`](./convert-parquet-to-csv) | How to convert Parquet to CSV | clickhouse-local |
| [`convert-parquet-to-json`](./convert-parquet-to-json) | How to convert Parquet to JSON | clickhouse-local |
| [`convert-parquet-to-jsonl`](./convert-parquet-to-jsonl) | How to convert Parquet to JSONL | clickhouse-local |
| [`convert-parquet-to-ndjson`](./convert-parquet-to-ndjson) | How to convert Parquet to NDJSON | clickhouse-local |
| [`convert-parquet-to-orc`](./convert-parquet-to-orc) | How to convert Parquet to ORC | clickhouse-local |
| [`convert-parquet-to-tsv`](./convert-parquet-to-tsv) | How to convert Parquet to TSV | clickhouse-local |
| [`convert-tsv-to-csv`](./convert-tsv-to-csv) | How to convert TSV to CSV | clickhouse-local |
| [`convert-tsv-to-json`](./convert-tsv-to-json) | How to convert TSV to JSON | clickhouse-local |
| [`convert-tsv-to-parquet`](./convert-tsv-to-parquet) | How to convert TSV to Parquet | clickhouse-local |

### Format definitions

| Folder | Companion article | Surface |
|---|---|---|
| [`orc-file-format`](./orc-file-format) | ORC file format | clickhouse-local |
| [`what-is-a-tsv-file`](./what-is-a-tsv-file) | What is a TSV file? | clickhouse-local |
| [`what-is-an-avro-file`](./what-is-an-avro-file) | What is an Avro file? | clickhouse-local |
| [`what-is-an-npy-file`](./what-is-an-npy-file) | What is an .npy file? | clickhouse-local |
| [`what-is-bson`](./what-is-bson) | What is a BSON file? | clickhouse-local |
| [`what-is-messagepack`](./what-is-messagepack) | What is MessagePack? | clickhouse-local |
| [`what-is-ndjson`](./what-is-ndjson) | What is NDJSON / JSON Lines? | clickhouse-local |
| [`what-is-protobuf`](./what-is-protobuf) | What is Protobuf? | clickhouse-local |

## Requirements

- `clickhouse` — install with [`clickhousectl`](https://clickhouse.com/docs/install):

  ```bash
  curl https://clickhouse.com/cli | sh   # install clickhousectl
  clickhousectl local use latest         # download ClickHouse and put it on your PATH
  ```

  This puts `clickhouse` on your PATH; invoke local mode as `clickhouse local`.
- For the Python (chDB) examples: `pip install chdb pandas pyarrow`.
