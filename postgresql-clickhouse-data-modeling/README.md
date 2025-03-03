This is an example of a migration from PostgreSQL to ClickHouse using PeerDB. 

# Dataset

The example is using StackOverflow dataset. Be aware that is large and will a few Gb when inserted in PostgreSQL. 

# How to run it

Execute the script [run-cdc.sh](./run-cdc.sh) to run the example locally on your machine. 

The script will pull the Docker images required for the application to run and deploy the application using docker compose. 

Then a script download the StackOverflow dataset and insert it to the PostgreSQL database. This takes a few minutes to run. 

After that, a PostgreSQL peer and a ClickHouse peer are created in PeerDB and a mirror is configured to start synchronizing the data. After a few minutes the initial load should be completed and the data is synchronized between PostgreSQL and ClickHouse. Now all the CRUD operations on PostgreSQL are replicated in the ClickHouse database.

You can access the PeerDB UI at http://localhost:3000

You can access the ClickHouse DB using this command: `docker exec -it clickhouse sh -c "clickhouse-client --host localhost"` 

You can access the PostgreSQL instance using this command: `docker exec -it postgres sh -c "psql -U admin -d clickhouse_pg_db"`

# How to simulate activity

You can simulate activity on StackOverflow - which generates new operations in PostgreSQL - using the script [generate_activity.sh](./generate-activity.sh). Check the output to see what entries have been updated, inserted or deleted in PostgreSQL. After a few seconds, the operations are replicated in ClickHouse. 




