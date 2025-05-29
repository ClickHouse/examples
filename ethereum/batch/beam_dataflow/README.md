# Beam (Dataflow) for Ethereum

Example batch Apache Beam (GCP Dataflow) job to move Ethereum data from BigQuery to ClickHouse.

If you want to test queries without using Beam, you can [directly insert CSVs from GCS](../inserts/README.md).

## Example execution

Create a Google Cloud Service Account with the following permissions:
 - BigQuery Data Viewer
 - Storage Object Admin
 - Dataflow Admin

Create a service account key and save it as a JSON file.

Export the service account key as an environment variable:

```bash
export GOOGLE_APPLICATION_CREDENTIALS="path/to/service-account-key.json"
```

Run the job using `uv`:

```bash
uv runs sync_clickhouse.py \
--table my_project.crypto_ethereum.blocks \
--target_table ethereum.blocks \
--clickhouse_host 3.16.135.104 \
--clickhouse_password clickhouse \
--region us-central1 \
--runner DataflowRunner \
--project pmm-project-377716 \
--temp_location gs://pme-internal/temp/beamtesttmp \
--requirements_file requirements.txt
```

Note that connections are made over HTTP(S), using TLS & port 8443 by default.

If using a non-secured ClickHouse instance, add the following flags:

```
--clickhouse_no_ssl \
--clickhouse_port=8123
```