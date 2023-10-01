# How the script works in detail

Here we document some of the implementation details in more detail.



## General function call structure of the initial version of the script

The script’s main function is [load_files](https://github.com/ClickHouse/examples/blob/76bd74ebf08cb0d65b96a758c72bf470947cbbe6/large_data_loads/src/load_files.py#L74):
```python
def load_files(url, rows_per_batch, db_dst, tbl_dst, …):
① staging_tables = create_staging_tables(db_dst, tbl_dst, …)
② file_list = get_file_urls_and_row_counts(url, …)
   for [file_url, file_row_count] in file_list:
③     if file_row_count > rows_per_batch:
           load_file_in_batches(file_url, file_row_count, 
                                rows_per_batch,...)
       else:
           load_file_complete(file_url, …)
```
The function is called with a `url` containing a [glob pattern](https://en.wikipedia.org/wiki/Glob_(programming)) indicating the set of files whose content you want to load into the target ClickHouse table `table_dst` within the `db_dst` database. Note that the target ClickHouse table `tbl_dst` needs to exist before calling the script. The batch size in a count of rows is configured with the `rows_per_batch` parameter.

The function first ① creates all staging tables, and then ② calls the [get_file_urls_and_rowcounts](https://github.com/ClickHouse/examples/blob/76bd74ebf08cb0d65b96a758c72bf470947cbbe6/large_data_loads/src/load_files.py#L99) function to retrieve the list of urls for all existing files matching the glob pattern together with their individual row count. We then use one of two functions for loading each file from the list.

Note that, depending on the number and the size of to-be-loaded files, the [get_file_urls_and_rowcounts](https://github.com/ClickHouse/examples/blob/76bd74ebf08cb0d65b96a758c72bf470947cbbe6/large_data_loads/src/load_files.py#L99) function does one, potentially huge and relatively slow [scan](https://github.com/ClickHouse/examples/blob/76bd74ebf08cb0d65b96a758c72bf470947cbbe6/large_data_loads/src/load_files.py#L112) for retrieving the file paths and individual row counts. While this is still acceptable, when the actual data transfer takes days, luckily, we drastically improved the efficiency and performance of this in [23.8](https://clickhouse.com/blog/clickhouse-release-23-08#direct-import-from-archives-nikita-keba-antonio-andelic-pavel-kruglov).

 

In case `③ `the file’s row count is larger than the configured batch size, we call the [load_file_in_batches](https://github.com/ClickHouse/examples/blob/76bd74ebf08cb0d65b96a758c72bf470947cbbe6/large_data_loads/src/load_files.py#L132) function:
```python
def load_file_in_batches(file_url, file_row_count, rows_per_batch,...):
  row_start = 0
  row_end = rows_per_batch
    while row_start < file_row_count:
①    command = create_batch_load_command(file_url, …, row_start, row_end, …)
      try:
②      load_one_batch(command,...)
③      except BatchFailedError as err:
            logger.error(f"{err=}")
            logger.error(f"Failed file: {file_url}")
            logger.error(f"Failed row block: {row_start} to {row_end}")
        row_start = row_end
        row_end = row_end + rows_per_batch
```
This function iterates with the configured `rows_per_batch` size over the file’s rows by loading them batch-wise by ① calling [create_batch_load_command](https://github.com/ClickHouse/examples/blob/76bd74ebf08cb0d65b96a758c72bf470947cbbe6/large_data_loads/src/load_files.py#L204) to create a corresponding SQL load command and ② calling [load_one_batch](https://github.com/ClickHouse/examples/blob/76bd74ebf08cb0d65b96a758c72bf470947cbbe6/large_data_loads/src/load_files.py#L171) with that command. ③ In case (even after a few retries) the batch fails, we log this and just continue with the next batch until all rows from the current file are processed.

In our main function, [load_files](https://github.com/ClickHouse/examples/blob/76bd74ebf08cb0d65b96a758c72bf470947cbbe6/large_data_loads/src/load_files.py#L74), in step `③, `we check if we can load a file with a single, more efficient batch transfer. In that case, we call the [load_file_complete](https://github.com/ClickHouse/examples/blob/76bd74ebf08cb0d65b96a758c72bf470947cbbe6/large_data_loads/src/load_files.py#L157) function:
```python
def load_file_complete(file_url,…):
①  command = create_batch_load_commandfile_url,…)
    try:
②      load_one_batch(command, …)
③  except BatchFailedError as err:
        logger.error(f"{err=}")
        logger.error(f"Failed file: {file_url}")
```
The function `① `first creates a more efficient single file SQL load command by calling the [create_batch_load_command](https://github.com/ClickHouse/examples/blob/76bd74ebf08cb0d65b96a758c72bf470947cbbe6/large_data_loads/src/load_files.py#L204) function, and then ② calls the [load_one_batch](https://github.com/ClickHouse/examples/blob/76bd74ebf08cb0d65b96a758c72bf470947cbbe6/large_data_loads/src/load_files.py#L171) function with that command. `③ `If the batch transfer fails, even after a few retries, we log this and continue within the [load_files](https://github.com/ClickHouse/examples/blob/76bd74ebf08cb0d65b96a758c72bf470947cbbe6/large_data_loads/src/load_files.py#L74) function with the next file until all files are processed.

The [load_one_batch](https://github.com/ClickHouse/examples/blob/76bd74ebf08cb0d65b96a758c72bf470947cbbe6/large_data_loads/src/load_files.py#L171) function implements the core of our batch transfer and retry logic:
```python
def load_one_batch(batch_command, staging_tables, client):
    retries = 3
    attempt = 1
    while True:
        for d in staging_tables:
①          client.command(
                f"TRUNCATE TABLE {d['db_staging']}.{d['tbl_staging']}")
        try:
②          client.command(batch_command)
        for d in staging_tables:
③          copy_partitions(d['db_staging'], d['tbl_staging'], 
                            d['db_dst'],     d['tbl_dst'],...)
        return
④  except Exception as err:
        logger.error(f"Unexpected {err=}, {type(err)=}")
        attempt = attempt + 1
        if attempt <= retries:
⑤          time.sleep(60)
            continue
⑥      else:
            raise BatchFailedError(
                f"Batch still failed after {retries} attempts.")
```
The function `①` first truncates all staging tables, then `②` inserts the current batch of rows into the main staging table (potentially triggering [cloned](https://github.com/ClickHouse/examples/blob/76bd74ebf08cb0d65b96a758c72bf470947cbbe6/large_data_loads/src/load_files.py#L301) materialized views inserting transformed data into their [target](https://github.com/ClickHouse/examples/blob/76bd74ebf08cb0d65b96a758c72bf470947cbbe6/large_data_loads/src/load_files.py#L299) staging tables), and on success, `③` copies all partitions from all staging tables into their corresponding target tables. If ④ the transfer in step `②` fails, we ⑤ wait a moment (to give transient issues time to resolve) and then retry the batch transfer. ⑥ If that batch transfer still doesn’t succeed after a number (default 3) of retries, we raise an error. We described above that the calling functions are handling this error by logging information about the failed batch and continuing with the next batch.





## Support for arbitrary partitioning keys

The script’s batching mechanism is independent of any [partitioning](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/custom-partitioning-key) scheme of the target table. Our script doesn’t create any partitions by itself. And also doesn’t require that each loaded file belongs to a specific partition. Instead, the target table can have any (or no) [custom partition key](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/custom-partitioning-key), which we duplicate in the staging table (which is a DDL-level [clone](https://github.com/ClickHouse/examples/blob/76bd74ebf08cb0d65b96a758c72bf470947cbbe6/large_data_loads/src/load_files.py#L280) of the target table). After each successful batch [transfer](https://github.com/ClickHouse/examples/blob/76bd74ebf08cb0d65b96a758c72bf470947cbbe6/large_data_loads/src/load_files.py#L171), we just [copy](https://github.com/ClickHouse/examples/blob/76bd74ebf08cb0d65b96a758c72bf470947cbbe6/large_data_loads/src/load_files.py#L445) over all (parts belonging to) partitions that were naturally created for the staging table during the ingest of data from the currently processed file. This means that overall exactly the same number of partitions is created for the target table as if we would insert all data (without using our script) directly into the target table. The following diagram sketches this:
![](copy_parts.png)
Before each batch transfer, we [drop](https://clickhouse.com/docs/en/sql-reference/statements/truncate) all parts from the staging table. 

A successful data transfer of a [single batch](https://github.com/ClickHouse/examples/blob/76bd74ebf08cb0d65b96a758c72bf470947cbbe6/large_data_loads/src/load_files.py#L180) ① creates some parts (indicated as yellow rectangles in the diagram above) for the staging table. These parts potentially belong to partitions. Partitions don’t exist by themselves in ClickHouse. Instead, each part indicates the partition it belongs to via its individual directory name (which is often referred to as the part’s name). The data for each part is stored within a directory, whose name [is a combination of](https://github.com/ClickHouse/ClickHouse/blob/ff66d2937617f2c66e57b9539f34b6e4ea8ed183/src/Storages/MergeTree/MergeTreeData.h#L126) `partition-id`, min and max [block](https://clickhouse.com/docs/en/development/architecture#block) ids, and [merge-level](https://clickhouse.com/blog/supercharge-your-clickhouse-data-loads-part1), all separated by the `_` character. In the example in the diagram above, the target table (and, therefore, also the staging table) uses the [month](https://clickhouse.com/docs/en/sql-reference/functions/date-time-functions#tomonth) of a [DateTime](https://clickhouse.com/docs/en/sql-reference/data-types/datetime) column value for [partitioning](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/custom-partitioning-key) the data. Therefore the name of each part directory starts with a (numeric) month indicating the part’s `partition-id`. In our example, the current batch transfer created one part belonging to the April (`4_…`) partition and 3 parts belonging to the September (`9_…`) partition. Because the data ingested from the currently processed file coincidentally contained rows with partitioning key values for exactly these two months. 

After the whole batch transfer succeeded, [per](https://github.com/ClickHouse/examples/blob/76bd74ebf08cb0d65b96a758c72bf470947cbbe6/large_data_loads/src/load_files.py#L447) existing partition in the staging table, we [use](https://github.com/ClickHouse/examples/blob/76bd74ebf08cb0d65b96a758c72bf470947cbbe6/large_data_loads/src/load_files.py#L471) a ([atomic](https://github.com/ClickHouse/ClickHouse/issues/4729)) [ALTER TABLE … ATTACH PARTITION … FROM …](https://clickhouse.com/docs/en/sql-reference/statements/alter/partition#attach-partition-from) operation to ② copy these new parts (indicated with a blue directory name) from the staging table to the target table, which already contains parts from previous batch transfers (indicated with black directory names belonging to the January-, April-, and September-partition). 

If the target table (and therefore also the staging table) doesn’t use a partition key, all parts belong to the same `all` partition. And all part directory names start with  `all_`. 

Note that eventually, in the background, the target table’s parts are ③ [merged](https://clickhouse.com/blog/supercharge-your-clickhouse-data-loads-part1#more-parts--more-background-part-merges) (per [level](https://clickhouse.com/blog/supercharge-your-clickhouse-data-loads-part1#more-parts--more-background-part-merges)) into larger parts. Parts belonging to different partitions are never merged with each other.

Also, note that [ClickHouse Cloud](https://clickhouse.com/cloud) stores all data [shared](https://clickhouse.com/blog/clickhouse-cloud-boosts-performance-with-sharedmergetree-and-lightweight-updates#clickhouse-cloud-enters-the-stage) in object storage. Copying parts doesn’t copy any data inside the object storage but simply creates additional links to the existing parts.  
