# Bench2Cost – ClickHouse Results Ingestion

`ingest_results.sh` loads benchmark result JSON files into a **ClickHouse** table.
It creates the database/table if needed and can optionally drop and recreate the table.

---

## Requirements

* **bash** (macOS/Linux)
* **jq** – for transforming JSON to SQL
* **clickhouse** client on PATH
  (if using a remote cluster, set the environment variables below)

Make sure you can run:
```bash
jq --version
clickhouse client --version
```

---

## Usage

```bash
./ingest_results.sh [--reset] <database> <table> [root_dir] [results_subdir]
```

* `--reset` – optional. Drop/recreate the table before loading.
* `<database>` – ClickHouse database name.
* `<table>` – ClickHouse table name.
* `[root_dir]` – optional. Defaults to `..` (parent directory of script).
* `[results_subdir]` – optional. Defaults to `results`.

---

## Environment variables

| Variable      | Default     | Description |
|---------------|------------|------------|
| CH_HOST       | localhost  | ClickHouse host |
| CH_USER       | default    | ClickHouse user |
| CH_PASSWORD   | (empty)    | ClickHouse password |
| CH_SECURE     | (empty)    | Set to 1/true/yes to enable `--secure` |


Example 1:
```bash
CH_HOST=myhost CH_USER=bench /ingest_results.sh --reset bench2cost costs .. results
```

Example 2:
```bash
CH_HOST=myhost CH_USER=bench /ingest_results.sh --reset bench2cost_1B costs .. results_1B
```

---

## What it does

* Ensures the database and table exist.
* If `--reset` is passed, drops and recreates the table.
* Scans `[root_dir]/*/[results_subdir]/*.json` for JSON files.
* Uses `jq` to transform each JSON file’s `costs[]` entries into `INSERT` statements.
* Inserts the data into ClickHouse.

---

## Notes

* Requires `jq` and `clickhouse client` on your PATH.
* All processing is done client-side; no external services are needed.
