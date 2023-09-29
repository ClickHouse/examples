# Script for reliable loading large volumes of data

This is a script introduced in a [blog](todo) for loading a large dataset with trillions of rows incrementally and reliably over a long period of time. 

## Examples

We provide an example of how to use the script with some large example data set [here](./examples/pypi/README.md).


## Usage

```shell
usage: load_files.py [-h] 
# ① ClickHouse connection settings
--host HOST 
--port PORT 
--username USERNAME 
--password PASSWORD 

# ② Data loading - main settings
--url URL # The url (which can contain glob patterns) specifying the set of files to be loaded.
--rows_per_batch ROWS_PER_BATCH # How many rows should be loaded within a single batch transfer.
--database DATABASE # Name of the target ClickHouse database.
--table TABLE # Name of the target ClickHouse table.

# ③ Data loading - optional settings
[--cfg.function CFG.FUNCTION] # Name of the table function for accessing the to-be-loaded files.
[--cfg.use_cluster_function_for_file_list] # Should the more efficient ...Cluster version of the table function be used for retrieving the file list?
[--cfg.cluster_name CFG.CLUSTER_NAME] # Name of the cluster in case the ...Cluster table function version is used for retrieving the file list.
[--cfg.format CFG.FORMAT] # Name of the file format used. 
[--cfg.structure CFG.STRUCTURE] # Structure of the file data.
[--cfg.select CFG.SELECT] # Custom SELECT clause for retrieving the file data.
[--cfg.where CFG.WHERE] # Custom WHERE clause for retrieving the file data.
[--cfg.query_settings CFG.QUERY_SETTINGS [CFG.QUERY_SETTINGS ...]] # Custom query-level settings.
```


