# Dataflow for Ethereum

Simple batch based Apache Beam job for ethereum data. Moves data from BigQuery to ClickHouse. Tested on batches but should work for all data types.


## Example execution

```bash
python -m sync_clickhouse --target_table ethereum.blocks --clickhouse_host <clickhouse_host> --clickhouse_password <password> --region us-central1 --runner DataflowRunner --project <GCE project> --temp_location gs://<bucket> --requirements_file requirements.txt
```