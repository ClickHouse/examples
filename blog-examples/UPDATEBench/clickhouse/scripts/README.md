# ClickHouse update benchmarks

This directory contains scripts to run the update benchmarks for ClickHouse.

---

## 1. Create the Base Table

The first step is to create and populate the `lineitem_base_tbl_1part` table, which uses the TPC‑H `lineitem` dataset at **scale factor 100** (~600M rows, ~60 GiB uncompressed).

```bash
cd clickhouse-fast-updates
./init.sh
```

This script:

1. Creates the base table.
2. Loads the TPC‑H `lineitem` table from S3.
3. Verifies that the expected row count, part counts, and data size matches.

Example output:

```
┌─row_count─────┬─part_count─┬─size_uncomp─┬─size_comp─┐
│ 600.04 million│ 1.00       │ 57.85 GiB   │ 26.69 GiB │
└───────────────┴────────────┴─────────────┴───────────┘
```

---

## 2. Run Benchmarks

Benchmarks are divided into **single-row updates** and **multi-row updates**.

### 2.1 Single-Row Updates

```bash
cd clickhouse-fast-updates/single-row-updates
./run_updates_sequential.sh
```

This will:

- Sequentially run each update query from `10x1` on the base table.
- Measure both **update runtime** and **subsequent query latency**.
- Save results as JSON in the `results` folder.



### 2.2 Multi-Row Updates

```bash
cd clickhouse-fast-updates/multi-row-updates
./run_updates_sequential.sh
```


Results are written as structured JSON for analysis.

---


## 3. Results

- All results are exported as JSON to the `results/` directories.

---

