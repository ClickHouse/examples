import clickhouse_connect
import time
import logging


# Logger Configuration
LOGGER_FILENAME = "log.log"

logging.basicConfig(filename=LOGGER_FILENAME, format="%(asctime)s %(message)s", filemode='a')
logFormatter = logging.Formatter("%(asctime)s %(message)s")
logger = logging.getLogger()
logger.setLevel(logging.DEBUG)

consoleHandler = logging.StreamHandler()
consoleHandler.setFormatter(logFormatter)
logger.addHandler(consoleHandler)


def main():






    client = clickhouse_connect.get_client(
        host='f1e1rfvwho.us-central1.gcp.clickhouse-staging.com',
        port=8443,
        username='default',
        password='XXX')

    load_files(
        # url = 'https://storage.googleapis.com/clickhouse_public_datasets/pypi/file_downloads/sample/2023/{0..61}-*.parquet',
        url = 'https://storage.googleapis.com/clickhouse_public_datasets/pypi/file_downloads/sample/2023/{0..1}-*.parquet',
        # rows_per_batch = 1000000,
        rows_per_batch = 100000,
        db_dst =  'default',
        # table = 'T1',
        table_dst = 'pypi',
        format = 'Parquet',
        structure = 'timestamp DateTime64(6), country_code LowCardinality(String), url String, project String, `file.filename` String, `file.project` String, `file.version` String, `file.type` String, `installer.name` String, `installer.version` String, python String, `implementation.name` String, `implementation.version` String, `distro.name` String, `distro.version` String, `distro.id` String, `distro.libc.lib` String, `distro.libc.version` String, `system.name` String, `system.release` String, cpu String, openssl_version String, setuptools_version String, rustc_version String,tls_protocol String, tls_cipher String',
        select = """
            timestamp,
            country_code,
            url,
            project,
            (ifNull(file.filename, ''), ifNull(file.project, ''), ifNull(file.version, ''), ifNull(file.type, '')) AS file,
            (ifNull(installer.name, ''), ifNull(installer.version, '')) AS installer,
            python AS python,
            (ifNull(implementation.name, ''), ifNull(implementation.version, '')) AS implementation,
            (ifNull(distro.name, ''), ifNull(distro.version, ''), ifNull(distro.id, ''), (ifNull(distro.libc.lib, ''), ifNull(distro.libc.version, ''))) AS distro,
            (ifNull(system.name, ''), ifNull(system.release, '')) AS system,
            cpu AS cpu,
            openssl_version AS openssl_version,
            setuptools_version AS setuptools_version,
            rustc_version AS rustc_version,
            tls_protocol,
            tls_cipher
        """,
        settings={'input_format_null_as_default': 1,
                  'input_format_parquet_import_nested': 1},
        client = client)


#-----------------------------------------------------------------------------------------------------------------------
# Main function
#-----------------------------------------------------------------------------------------------------------------------
def load_files(url, rows_per_batch, db_dst, table_dst, client, format, structure, select, settings):
    # Step ①: Create a temp table
    db_temp = db_dst
    table_temp = table_dst + '_temp'
    create_temp_table(db_dst, table_dst, db_temp, table_temp, client)
    # Step ②: Get full path urls and row counts for all to-be-loaded files
    logger.info(f"Fetching all files and row counts")
    file_list = get_file_urls_and_row_counts(url, format ,client)
    logger.info(f"Done")
    for [file_url, file_row_count] in file_list:
        logger.info(f"Processing file: {file_url}")
        logger.info(f"Row count: {file_row_count}")
        # Step ③: Load a single file (potentially in batches)
        if file_row_count > rows_per_batch:
            load_file_in_batches(file_url, file_row_count, rows_per_batch, db_temp, table_temp, db_dst, table_dst, format, structure, select, settings, client)
        else:
            load_file_complete(file_url, db_temp, table_temp, db_dst, table_dst, format, structure, select, settings, client)
        break


#-----------------------------------------------------------------------------------------------------------------------
# Load files - Step ①: Create a temp table
#-----------------------------------------------------------------------------------------------------------------------
def create_temp_table(db_src, table_src, db_dst, table_dst, client):
    result = client.query("""
    SELECT replaceOne(create_table_query, concat({db_src:String}, '.', {table_src:String}), concat({db_dst:String}, '.', {table_dst:String}))
    FROM system.tables
    WHERE database = {db_src:String} AND name = {table_src:String}
    """, parameters = {'db_src' : db_src, 'table_src' : table_src, 'db_dst' : db_dst, 'table_dst' : table_dst})

    ddl_for_temp_table = result.result_rows[0][0]
    logger.info(f"ddl_for_temp_table:")
    logger.info(f"{ddl_for_temp_table}")
    try:
        client.command(ddl_for_temp_table)
    except Exception as err:
        if f"{err=}".find("TABLE_ALREADY_EXISTS") > -1:
            logger.warning(f"{err=}")
            return
        else:
            logger.error(f"Unexpected {err=}, {type(err)=}")
            raise


#-----------------------------------------------------------------------------------------------------------------------
# Load files - Step ②: Get full path urls and row counts for all to-be-loaded files
#-----------------------------------------------------------------------------------------------------------------------
def get_file_urls_and_row_counts(url, format, client):
    result = client.query("""
    WITH
        splitByString('://', {url:String})[1] AS _protocol,
        domain({url:String}) AS _domain
    SELECT
        concat(_protocol, '://', _domain, '/', _path) as file,
        count() as count
    FROM s3Cluster(
        'default',
        {url:String},
        {format:String})
    GROUP BY 1
    ORDER BY 1
    """, parameters = {'url' : url, 'format' : format})
    return result.result_rows


#-----------------------------------------------------------------------------------------------------------------------
# Load files - Step ③.Ⓐ: Load a single file in batches (because its file_row_count  > rows_per_batch)
#-----------------------------------------------------------------------------------------------------------------------
def load_file_in_batches(file_url, file_row_count, rows_per_batch, db_temp, table_temp, db_dst, table_dst, format,
                         structure, select, settings, client):
    row_start = 0
    row_end = rows_per_batch
    while row_start < file_row_count:
        command = create_batch_load_command(file_url, row_start, row_end, db_temp, table_temp, format, structure, select, settings)
        try:
            logger.debug(f"Batch loading file: {file_url}")
            logger.debug(f"Batch row block: {row_start} to {row_end}")
            logger.debug(f"Batch command: {command}")
            load_one_batch(command, db_temp, table_temp, db_dst, table_dst, client)
        except BatchFailedError as err:
            logger.error(f"{err=}")
            logger.error(f"Failed file: {file_url}")
            logger.error(f"Failed row block: {row_start} to {row_end}")
        row_start = row_end
        row_end = row_end + rows_per_batch


#-----------------------------------------------------------------------------------------------------------------------
# Load a single file in batches (Step ③.Ⓐ): Create the SQL load command
#-----------------------------------------------------------------------------------------------------------------------
def create_batch_load_command(file_url, row_start, row_end, db_temp, table_temp, format, structure, select, settings):
    extra_settings = {'input_format_parquet_preserve_order' : 1,
                      'parallelize_output_from_storages' : 0}

    command = f"""
            INSERT INTO {db_temp}.{table_temp}
            SELECT {select} FROM s3('{file_url}', '{format}', '{structure}')
            WHERE rowNumberInAllBlocks() >= {row_start}
              AND rowNumberInAllBlocks()  < {row_end}
            SETTINGS {as_string({**settings, **extra_settings})}
        """
    return command


#-----------------------------------------------------------------------------------------------------------------------
# Load files - Step ③.Ⓑ: Load a single file completely in one batch (because its file_row_count  < rows_per_batch)
#-----------------------------------------------------------------------------------------------------------------------
def load_file_complete(file_url, db_temp, table_temp, db_dst, table_dst, format, structure, select, settings, client):
        command = create_complete_load_command(file_url, db_temp, table_temp, format, structure, select, settings)
        try:
            load_one_batch(command, db_temp, table_temp, db_dst, table_dst, client)
        except BatchFailedError as err:
            logger.error(f"{err=}")
            logger.error(f"Failed file: {file_url}")


#-----------------------------------------------------------------------------------------------------------------------
# Load a single file in batches (Step ③.Ⓑ): Create the SQL load command
#-----------------------------------------------------------------------------------------------------------------------
def create_complete_load_command(file_url, db_temp, table_temp, format, structure, select, settings):
    command = f"""
            INSERT INTO {db_temp}.{table_temp}
            SELECT {select} FROM s3('{file_url}', '{format}', '{structure}')
            SETTINGS {as_string(settings)}
        """
    return command


#-----------------------------------------------------------------------------------------------------------------------
# Load one batch for a single file (Step ③.Ⓐ or Step ③.Ⓑ)
#-----------------------------------------------------------------------------------------------------------------------
def load_one_batch(batch_command, db_temp, table_temp, db_dst, table_dst, client):
    retries = 3
    attempt = 1
    while attempt <= retries:
        # Step ①: Drop all parts from the temp table
        client.command(f"TRUNCATE TABLE {db_temp}.{table_temp}")
        try:
            # Step ②: load one batch
            client.command(batch_command)
            # Step ③: copy parts (of all partitions) from temp table to destination table
            copy_partitions(db_temp, table_temp, db_dst, table_dst, client)
            # Success, nothing more todo here
            return
        except Exception as err:
            logger.error(f"Unexpected {err=}, {type(err)=}")
            # wait a bit for transient issues to resolve, then retry the batch
            logger.info("Going to sleep for 60s")
            time.sleep(60)
            attempt = attempt + 1
            logger.info(f"Starting attempt {attempt} of {retries}")
            continue
           # Step ①: Drop all parts from the temp table
    # we land here in case all retries are used unsuccessfully
    raise BatchFailedError(f"Batch still failed after {retries} attempts.")

#-----------------------------------------------------------------------------------------------------------------------
#-----------------------------------------------------------------------------------------------------------------------
# Copying all existing parts (for all partitions) from one table to another
#-----------------------------------------------------------------------------------------------------------------------
#-----------------------------------------------------------------------------------------------------------------------


#-----------------------------------------------------------------------------------------------------------------------
# Copy all existing parts (for all partitions) from one table to another
#-----------------------------------------------------------------------------------------------------------------------
def copy_partitions(db_src, table_src, db_dst, table_dst, client):
    partition_ids = get_partition_ids(db_src, table_src, client)
    for [partition_id] in partition_ids:
        logger.debug(f"Copy partition: {partition_id}")
        copy_partition(partition_id, db_src, table_src, db_dst, table_dst, client)


#-----------------------------------------------------------------------------------------------------------------------
# Helper function - get names of all existing partitions for a table
#-----------------------------------------------------------------------------------------------------------------------
def get_partition_ids(db, table, client):
    result = client.query("""
        SELECT partition
        FROM system.parts
        WHERE database = {db:String}
          AND table = {table:String}
        GROUP BY partition
        ORDER BY partition
    """, parameters = {'db' : db, 'table' : table})
    return result.result_rows


#-----------------------------------------------------------------------------------------------------------------------
# Helper function - copy a single partition from one table to another
#-----------------------------------------------------------------------------------------------------------------------
def copy_partition(partition_id, db_src, table_src, db_dst, table_dst, client):
    command = f"""
        ALTER TABLE {db_dst}.{table_dst}
        ATTACH PARTITION {partition_id}
        FROM {db_src}.{table_src}"""
    client.command(command)


#-----------------------------------------------------------------------------------------------------------------------
#-----------------------------------------------------------------------------------------------------------------------
# Misc helper functions
#-----------------------------------------------------------------------------------------------------------------------
#-----------------------------------------------------------------------------------------------------------------------


#-----------------------------------------------------------------------------------------------------------------------
# Helper function - transform dictionary items into comma-separated settings-fragment for SQL SETTINGS clause
# {'a' : 23, 'b' : 42} -> "'a' = 23, 'b' = 42"
#-----------------------------------------------------------------------------------------------------------------------
def as_string(settings):
    settings_string = ''
    for key in settings:
        settings_string += str(key) + ' = ' + str(settings[key]) + ', '
    return settings_string[:-2]


#-----------------------------------------------------------------------------------------------------------------------
# Our dedicated exception for indicating that a batch failed even after a few retries
#-----------------------------------------------------------------------------------------------------------------------
class BatchFailedError(Exception):
    pass



main()





