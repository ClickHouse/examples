# UK Property Prices Dataset

This folder contains an example dataset for **ClickHouse Parallel Replica Benchmarks**.  
It is based on UK property price data and comes with helper scripts and queries for benchmarking.

---

## Contents

- `load_data.sh` — creates schema and loads the dataset into ClickHouse.
- `load_examples.sh` — example calls for load_data.sh.
- `aggregation.sql` — aggregation query used for benchmarking horizontal scaling.
- `aggregation_simple.sql` — simplified aggregation query used for benchmarking vertical scaling.

---

## Loading the dataset

The helper script `load_data.sh` automatically:

1. Creates a new database named according to the scale:
   - `uk_b1`   → 1 billion rows
   - `uk_b10`  → 10 billion rows
   - `uk_b30`  → 30 billion rows
   - `uk_b50`  → 50 billion rows
   - `uk_b100` → 100 billion rows
   - `uk_t1`   → 1 trillion rows
2. Creates the main benchmark table inside that database.
3. Loads the specified number of rows into the table.

Example: to load **10 billion rows** into database `uk_b10`:

```bash
./load_data.sh 10000000000