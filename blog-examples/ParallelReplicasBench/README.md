# ClickHouse Parallel Replica Benchmarks

This repository contains a benchmarking framework for testing **ClickHouse parallel replicas** under different scaling configurations.  
It automates query execution, stats collection, and summary generation into structured JSON files for later analysis.

---

## Features

- Runs SQL queries on ClickHouse clusters with varying:
  - Node counts (`--max_parallel_replicas`)
  - Core counts (`--max_threads`)
- Supports both **horizontal** (vary nodes) and **vertical** (vary cores) scaling.
- Collects per-replica execution stats via a dedicated `aggregation_stats.sql` query.
- Aggregates results into a clean, skimmable JSON summary:
  - Cold run vs hot runs
  - Replica memory usage, bytes read, network traffic
  - Work distribution (`replica_percentage_processed`)
  - Replica temperature distribution (hot/warm/cold)
- Human-readable + raw statistics side by side for each run.

---

## Requirements

- [ClickHouse client](https://clickhouse.com/docs/en/interfaces/cli) available as `clickhouse client`
- [`jq`](https://stedolan.github.io/jq/) installed for JSON processing
- A running ClickHouse cluster accessible via environment variables:

```bash
export CH_HOST="my.clickhouse.host"
export CH_USER="default"
export CH_PASSWORD="..."
```

-  ⚠️ This script does not provision or resize your cluster. It only toggles query settings (max_parallel_replicas, max_threads) on an existing cluster. Make sure your cluster has enough replicas and cores for the largest configuration in your benchmark.


- Example:
```
./bench_matrix.sh \
  ./results/2025-08-23_combined_uk_b10_n1-10-20_c8-32-89_r5_cachedrop \
  uk_b10 \
  ./datasets/uk_property_prices/aggregation.sql \
  5 \
  "1 10 20" \
  "8 32 89" \
  356 \
  aws \
  us-east-2 \
  true
```
For this run your cluster must already have:
- ≥ 20 parallel replicas (nodes)
- each with ≥ 89 CPU cores

The script will only enable/disable existing nodes and cores through query settings (max_parallel_replicas, max_threads).

---

## Example datasets

This repository comes with ready-to-use example datasets under `datasets/`.  
They are not pre-loaded — you need to run the provided scripts before benchmarking.

### UK Property Prices

Folder: `datasets/uk_property_prices/`

- `load_data.sh` — creates schema and loads the dataset into ClickHouse.
- `load_examples.sh` — example calls for load_data.sh.
- `aggregation.sql` — main benchmark query.
- `aggregation_simple.sql` — simplified variant of the query for vertical scaling experiments.

➡️ See the dataset’s own [README.md](datasets/uk_property_prices/README.md) for full instructions.

### Other datasets

We plan to add additional datasets (e.g., Bluesky, …).  
Each dataset folder contains its own `README.md` with setup and query details.

---

## How it works

For each `(nodes × cores)` combination:
1. The target query is executed multiple times (`runs_per_combination`).
2. The **first run** is always treated as the **cold run**:
   - executed with `enable_filesystem_cache=0` → bypasses filesystem cache
   - guarantees a fair baseline independent of prior cache state
3. All subsequent runs are **hot runs**:
   - executed with `enable_filesystem_cache=1` → may benefit from cache
4. Query runtimes are recorded:
   - `cold` = first run  
   - `hot` = fastest run among runs 2..N  
   - `hot_avg` = average of all runs 2..N  
5. For both cold and hot, per-replica stats are collected and aggregated:
   - average memory, bytes read, and network traffic (excluding initiator node where appropriate)  
   - work distribution across replicas  
   - replica temperature distribution (`cold`, `warm`, `hot`)  
   - initiator node stats (rows/s, network recv)  

All results are written into the `results_dir`, including:
- per-run raw and pretty JSON stats under `stats/`
- per-combo summary JSON files
- one consolidated `summary_matrix-...json` covering the full experiment

---

## Cache control

The script has two layers of cache handling:

- **Per-run (always enforced):**  
  The very first run of each `(nodes × cores)` combination is cold (`enable_filesystem_cache=0`).  
  This ensures there is always a guaranteed cold baseline, even if caches are not cleared globally.

- **Global (optional):**  
  If `DROP_CACHES=true`, the script will flush ClickHouse caches between configurations:  
  - filesystem cache  
  - mark cache  
  - query condition cache  

If `DROP_CACHES=false`, caches are not flushed between matrix configurations.  
This means hot runs may become progressively hotter over time, but the cold baseline remains unaffected.

## Flow: cold vs hot selection (per combination)
```mermaid
flowchart TD
    A[Start combo (N nodes, C cores)] --> B{DROP_CACHES?}
    B -- true --> C[Drop FS/Mark/QueryCond caches on cluster]
    B -- false --> D[Skip global cache drop]
    C --> E
    D --> E

    subgraph "Runs 1..R (runs_per_combination)"
      E[Run #1: enable_filesystem_cache=0] --> F[Record time t1, store raw/pretty stats]
      F --> G[Run #2..R: enable_filesystem_cache=1]
      G --> H[Record times t2..tR, store raw/pretty stats]
    end

    H --> I[Aggregate]
    I --> J[cold  = t1]
    I --> K[hot   = min(t2..tR) (if R>1 else t1)]
    I --> L[hot_avg = avg(t2..tR) (if R>1 else null)]

    I --> M[Compute aggregated stats for cold & hot:
      - avg_replica_pct (incl. initiator)
      - replica_temperature_distribution (incl. initiator)
      - avg_replica_memory_excl_initiator
      - avg_replica_bytes_read (incl. initiator)
      - avg_replica_net_sent_excl_initiator
      - sum_replica_net_sent_excl_initiator
      - initiator_net_recv
      - initiator_rows_per_sec (pretty)
    ]

    J --> N[Write per-combo JSON]
    K --> N
    L --> N
    M --> N
    N --> O[Append to consolidated summary]
 ```

## Example usage

### Parameters

```
./bench_matrix.sh <results_dir> <query_db> <query_file> <runs_per_combination> <node_list> <cores_list> <ram_gb_per_node> <csp> <region> <drop_caches>
```

- **`<results_dir>`** — where all results will be written (summary + per-run JSONs).


- **`<query_db>`** — database containing the benchmarked table(s).
- **`<query_file>`** — SQL query file.

  ➡️ **Important:** you do **not** need to include the database name inside the query.  
  Just reference the table, e.g. `SELECT ... FROM my_table`.  
  The script automatically runs the query against `<query_db>`.  
  This makes it easy to benchmark **different data scales** just by switching the database.


- **`<runs_per_combination>`** — number of repeated runs per `(nodes × cores)` combo.

  ➡️ The **first run** is always executed with `enable_filesystem_cache=0` (cold, cache bypassed).  
  ➡️ All subsequent runs use `enable_filesystem_cache=1` (hot).  
  ➡️ The script records:
    - `cold` = first run  
    - `hot` = fastest among hot runs  
    - `hot_avg` = average across all hot runs


- **`<node_list>`** — space-separated list of node counts to test.
- **`<cores_list>`** — space-separated list of CPU core counts to test.
- **`<ram_gb_per_node>`** — RAM per node (metadata only, not enforced).
- **`<csp>`** — cloud provider tag (e.g. `aws`, `gcp`, `azure`).
- **`<region>`** — cloud region tag.



### Pure horizontal scaling (nodes)

```bash
./bench_matrix.sh \
  ./results/2025-08-23_horiz_uk_b10_n1-3-10-20-40-80-100_c89_r10_nocachedrop \
  uk_b10 \
  ./datasets/uk_property_prices/aggregation.sql \
  10 \
  "1 3 10 20 40 80 100" \
  "89" \
  356 \
  aws \
  us-east-2 \
  false
```


### Pure vertical scaling (cores)
```
./bench_matrix.sh \
  ./results/2025-08-23_vert_uk_b10_n1_c2-4-8-16-32-64-89_r10_nocachedrop \
  uk_b10 \
  ./datasets/uk_property_prices/aggregation_simple.sql \
  10 \
  "1" \
  "2 4 8 16 32 64 89" \
  356 \
  aws \
  us-east-2 \
  false
```

### Combined scaling (nodes × cores)

```
./bench_matrix.sh \
  ./results/2025-08-23_combined_uk_b10_n1-10-20_c8-32-89_r5_cachedrop \
  uk_b10 \
  ./datasets/uk_property_prices/aggregation.sql \
  5 \
  "1 10 20" \
  "8 32 89" \
  356 \
  aws \
  us-east-2 \
  true
```


### Output structure

```
results/2025-08-23_horiz_uk_b10_n1-3-.../
├── summary_matrix-nodes-1_3_10_20_40_80_100_cores-89_2025-08-23_134817.json
├── n10c89_2025-08-23_134817.json
├── n20c89_2025-08-23_134817.json
├── ...
└── stats/
    ├── n10c89_2025-08-23_134817/
    │   ├── run_1_pretty.json
    │   ├── run_1_raw.json
    │   ├── run_2_pretty.json
    │   └── ...
    └── n20c89_2025-08-23_134817/
```

###  Example JSON summary snippet

```
"n10c89": {
  "timing": { "cold": 2.570, "hot": 2.159, "hot_avg": 2.218500 },
  "runs": [2.570, 2.159, 2.278],
  "files": {
    "cold_pretty": "stats/n10c89_2025-08-23_134817/run_1_pretty.json",
    "cold_raw": "stats/n10c89_2025-08-23_134817/run_1_raw.json",
    "hot_pretty": "stats/n10c89_2025-08-23_134817/run_2_pretty.json",
    "hot_raw": "stats/n10c89_2025-08-23_134817/run_2_raw.json"
  },
  "cold_stats": {
    "avg_replica_pct": { "value": 10.00, "human": "10.00 %" },
    "replica_temperature_distribution": {"cold":10},
    "avg_replica_memory_excl_initiator": { "bytes": 681752649.44, "human": "650.17 MiB" },
    "avg_replica_bytes_read": { "bytes": 80272077.20, "human": "76.55 MiB" },
    "avg_replica_net_sent_excl_initiator": { "bytes": 222133.56, "human": "216.93 KiB" },
    "sum_replica_net_sent_excl_initiator": { "bytes": 1999202.00, "human": "1.91 MiB" },
    "initiator_net_recv": { "bytes": 2002091.00, "human": "1.91 MiB" },
    "initiator_rows_per_sec": "3.88 billion rows/s total"
  },
  "hot_stats": {
    "avg_replica_pct": { "value": 10.00, "human": "10.00 %" },
    "replica_temperature_distribution": {"hot":2,"warm":8},
    "avg_replica_memory_excl_initiator": { "bytes": 1303333536.78, "human": "1.21 GiB" },
    "avg_replica_bytes_read": { "bytes": 86181713.50, "human": "82.19 MiB" },
    "avg_replica_net_sent_excl_initiator": { "bytes": 252920.78, "human": "246.99 KiB" },
    "sum_replica_net_sent_excl_initiator": { "bytes": 2276287.00, "human": "2.17 MiB" },
    "initiator_net_recv": { "bytes": 2278881.00, "human": "2.17 MiB" },
    "initiator_rows_per_sec": "4.61 billion rows/s total"
  }
}
```

### License

MIT