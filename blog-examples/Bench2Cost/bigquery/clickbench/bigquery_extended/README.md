# BigQuery Benchmarks

As of 2025, Google BigQuery allows publishing benchmark results, which was not the case earlier.

## Setup

It’s not obvious how to create a database in the BigQuery console:  
databases are called **datasets**. You need to press on `⋮` next to your project, then choose **Create dataset**.

1. Create dataset `test`.  
2. Open the query editor and paste the contents of `create.sql`.  
   → It only takes ~2 seconds to create the table.

### Install Google Cloud CLI

```bash
wget --continue --progress=dot:giga https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz
tar -xf google-cloud-cli-linux-x86_64.tar.gz
./google-cloud-sdk/install.sh
source .bashrc
./google-cloud-sdk/bin/gcloud init
```

### Load the data

```bash
wget --continue --progress=dot:giga 'https://datasets.clickhouse.com/hits_compatible/hits.csv.gz'
gzip -d -f hits.csv.gz

echo -n "Load time: "
command time -f '%e' bq load --source_format CSV --allow_quoted_newlines=1 test.hits hits.csv
```

### Run the benchmark

```bash
./run_bq_bench.sh 2>&1 | tee log.txt
```

---

## Capturing table size

You can capture dataset size with:

```bash
bq show --format=prettyjson test.hits \
  | jq '{
      table: .tableReference.tableId,
      numRows: (.numRows|tonumber),
      numActiveLogicalBytes: (.numActiveLogicalBytes|tonumber),
      numActivePhysicalBytes: (.numActivePhysicalBytes|tonumber),
      numLongTermLogicalBytes: (.numLongTermLogicalBytes|tonumber),
      numLongTermPhysicalBytes: (.numLongTermPhysicalBytes|tonumber)
    }'
```

### Example output

```json
{
  "table": "hits",
  "numRows": 99997497,
  "numActiveLogicalBytes": 101369915641,
  "numActivePhysicalBytes": 9410688671,
  "numLongTermLogicalBytes": 0,
  "numLongTermPhysicalBytes": 0
}
```

### Interpreting the numbers

- **Active vs Long-term**  
  - **Active** = data modified or loaded in the last 90 days.  
  - **Long-term** = data unchanged for more than 90 days.  
  BigQuery automatically charges the lower long-term rate for cold data.

- **Logical vs Physical**  
  - **Logical bytes** = size of the raw uncompressed data (what you think of as the “dataset size”).  
  - **Physical bytes** = size of the compressed data on disk.  
  BigQuery lets you choose billing based on logical (default) or physical storage.

### Example in GB

From the example:

- **Logical (active)**: `101369915641` bytes ≈ **94.4 GiB**  
- **Physical (active)**: `9410688671` bytes ≈ **8.8 GiB**  

(1 GiB = 1,073,741,824 bytes)

This shows the dataset compresses roughly **10× smaller** on disk compared to the raw logical size.

---

## Storage Size Table

| Category        | Logical (raw, uncompressed) | Physical (compressed on disk) |
|-----------------|------------------------------|--------------------------------|
| Active storage  | 94.4 GiB                     | 8.8 GiB                        |
| Long-term (>90d)| 0 GiB                        | 0 GiB                          |
