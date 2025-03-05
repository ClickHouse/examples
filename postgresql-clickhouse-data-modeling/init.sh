#!/bin/sh 

# # Create and activate a Python virtual environment
VENV_DIR="venv"
python3 -m venv $VENV_DIR
. $VENV_DIR/bin/activate

# Install dependencies
pip install -r python/requirements.txt

# Load the data into PostgreSQL
python python/import_parquet.py clickhouse_pg_db admin password localhost 5432 100000

echo "Creating the ClickHouse database"
docker exec -it clickhouse sh -c "clickhouse-client --host localhost --query 'CREATE DATABASE IF NOT EXISTS stackoverflow'"

echo "Creating the PostgreSQL database peer"
curl --request POST \
  --url http://localhost:3000/api/v1/peers/create \
  --header 'Content-Type: application/json' \
  --data '{
	"peer": {
		"name": "postgres",
		"type": 3,
		"postgres_config": {
			"host": "host.docker.internal",
			"port": 5432,
			"user": "admin",
			"password": "password",
			"database": "clickhouse_pg_db"
		}
	},
	"allow_update":false
}'


echo "Creating the ClickHouse database peer"
curl --request POST \
  --url http://localhost:3000/api/v1/peers/create \
  --header 'Content-Type: application/json' \
  --data '{
	"peer": {
		"name": "clickhouse",
		"type": 8,
		"clickhouse_config": {
			"host": "host.docker.internal",
			"port": 9000,
			"user": "default",
			"database": "stackoverflow",
			"disable_tls": true
		}
	},
	"allow_update":false
}'

echo "Creating the PeerDB mirror"
curl --request POST \
  --url localhost:3000/api/v1/flows/cdc/create \
  --header 'Content-Type: application/json' \
  --data '
{
"connection_configs": {
  "flow_job_name": "mirror_api_kick_off",
  "source_name": "postgres", 
  "destination_name": "clickhouse",
  "table_mappings": [
   {
      "source_table_identifier": "public.posts",
      "destination_table_identifier": "posts"
    },
    {
      "source_table_identifier": "public.users",
      "destination_table_identifier": "users"
    },
    {
      "source_table_identifier": "public.votes",
      "destination_table_identifier": "votes"
    },
    {
      "source_table_identifier": "public.comments",
      "destination_table_identifier": "comments"
    }
  ],
  "idle_timeout_seconds": 10,
  "publication_name": "",
  "do_initial_snapshot": true,
  "snapshot_num_rows_per_partition": 5000,
  "snapshot_max_parallel_workers": 4,
  "snapshot_num_tables_in_parallel": 4,
  "resync": false,
  "initial_snapshot_only": false,
  "soft_delete_col_name": "_peerdb_is_deleted",
  "synced_at_col_name": "_peerdb_synced_at"
}
}'
echo "Done"

