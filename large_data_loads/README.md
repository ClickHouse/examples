# ClickLoad

Orchestration for loading a large dataset with trillions of rows incrementally and reliably over a long period of time. 

We described the data loading orchestration mechanism used by the script in detail in a [blog](todo).


## Capabilities
 - Reliably import data from files hosted in a object storage bucket into ClickHouse
 - Supports any partitioning key, projections, and materialized views
 - Job queue for files to be imported. Scales linearly.

## Pre-requisites

- python3.10+
- clickhouse-client
- ClickHouse instance with support for [KeeperMap](https://clickhouse.com/docs/en/engines/table-engines/special/keeper-map) and [keeper_map_strict_mode](https://clickhouse.com/docs/en/engines/table-engines/special/keeper-map#updates)

- ~1GB of RAM per Keeper node per 1 million scheduled files in the KeeperMap backed job task table

## Installing

`pip install -r requirements.txt`

Pre-create tables in ClickHouse.

### Table Schemas for job task table

```sql
CREATE TABLE tasks
(
	file_path String,
	file_paths Array(String),
	worker_id String DEFAULT '',
	started_time DateTime DEFAULT 0,
	scheduled DateTime MATERIALIZED now()
)
ENGINE = KeeperMap('tasks')
PRIMARY KEY file_path;
```

## Running

### Scheduling files for ClickHouse import

```shell
usage: queue_files.py [-h] 
# ① ClickHouse connection settings for instance hosting the job task table
--host HOST 
--port PORT 
--username USERNAME 
--password PASSWORD 

# ② files scheduling settings
--file FILE # The file containing the set of object storage urls for the files to be loaded
--task_database DATABASE # Name of the ClickHouse database for the task table
--task_table TABLE # Name of the task table.
[--files_chunk_size_min SIZE] # How many files are atomically processed together at a minimum
[--files_chunk_size_max SIZE] # How many files are atomically processed together at a maximum
```

### Starting a worker that continuosly imports scheduled files into ClickHouse
```shell
usage: worker.py [-h] 
# ① ClickHouse connection settings for the target instance
--host HOST 
--port PORT 
--username USERNAME 
--password PASSWORD 

# ② data loading - main settings
--database DATABASE # Name of the target ClickHouse database
--table TABLE # Name of the target table.
--task_database DATABASE # Name of the ClickHouse database for the task table
--task_table TABLE # Name of the task table.
[--worker_id ID] # Unique id for this worker
[--files_chunk_size_max SIZE] # How many files are atomically processed together at a maximum

# ③ Data loading - optional settings
[--cfg.function CFG.FUNCTION] # Name of the table function for accessing the to-be-loaded files
[--cfg.bucket_access_key CFG.ACCESS_KEY] # Access key for the object storage bucket hosting the files to be loaded
[--cfg.bucket_access_secret CFG.ACCESS_SECRET] # Access secret for the object storage bucket hosting the files to be loaded
[--cfg.format CFG.FORMAT] # Name of the file format used
[--cfg.structure CFG.STRUCTURE] # Structure of the file data
[--cfg.select CFG.SELECT] # Custom SELECT clause for retrieving the file data
[--cfg.where CFG.WHERE] # Custom WHERE clause for retrieving the file data
[--cfg.query_settings CFG.QUERY_SETTINGS [CFG.QUERY_SETTINGS ...]] # Custom query-level settings
```

## Example

We provide an example of how to use the script with some large example data set [here](./examples/pypi/README.md).