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


    # staging_tables = create_staging_tables('default', 'pypi2', client)
    # print(staging_tables)
    #
    # return


    load_files(
        # url = 'https://storage.googleapis.com/clickhouse_public_datasets/pypi/file_downloads/sample/2023/{0..61}-*.parquet',
        # url = 'https://storage.googleapis.com/clickhouse_public_datasets/pypi/file_downloads/sample/2023/{0..1}-*.parquet',
        url = 'https://storage.googleapis.com/clickhouse_public_datasets/pypi/file_downloads/sample/2023/0-00000000000{1..2}*.parquet',
        rows_per_batch = 100000,
        # rows_per_batch = 1000000,
        db_dst =  'default',
        # table = 'T1',
        tbl_dst = 'pypi2',
        client = client,
        configuration = {
            'format' : 'Parquet',
            'structure' : 'timestamp DateTime64(6), country_code LowCardinality(String), url String, project String, `file.filename` String, `file.project` String, `file.version` String, `file.type` String, `installer.name` String, `installer.version` String, python String, `implementation.name` String, `implementation.version` String, `distro.name` String, `distro.version` String, `distro.id` String, `distro.libc.lib` String, `distro.libc.version` String, `system.name` String, `system.release` String, cpu String, openssl_version String, setuptools_version String, rustc_version String,tls_protocol String, tls_cipher String',
            'select' : """
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
            'settings' : {'input_format_null_as_default': 1,
                          'input_format_parquet_import_nested': 1}}
        )


#-----------------------------------------------------------------------------------------------------------------------
# Main function
#-----------------------------------------------------------------------------------------------------------------------
def load_files(url, rows_per_batch, db_dst, tbl_dst, client, configuration = {}):
    # Step ①: Create all necessary staging tables (and MV clones)
    staging_tables = create_staging_tables(db_dst, tbl_dst, client)
    # Step ②: Get full path urls and row counts for all to-be-loaded files
    logger.info(f"Fetching all files and row counts")
    file_list = get_file_urls_and_row_counts(url, configuration, client)
    logger.info(f"Done")
    for [file_url, file_row_count] in file_list:
        logger.info(f"Processing file: {file_url}")
        logger.info(f"Row count: {file_row_count}")
        # Step ③: Load a single file (potentially in batches)
        if file_row_count > rows_per_batch:
            load_file_in_batches(file_url, file_row_count, rows_per_batch, staging_tables, configuration, client)
        else:
            load_file_complete(file_url, staging_tables, configuration, client)
    # Cleanup: Drop all staging tables (and MV clones)
    drop_staging_tables(staging_tables, client)


#-----------------------------------------------------------------------------------------------------------------------
# Load files - Step ①: Create a staging table
#-----------------------------------------------------------------------------------------------------------------------
def create_tbl_clone(db_src, tbl_src, db_dst, tbl_dst, client):

    # REPLACE in case a previous run got stopped before cleanup
    result = client.query("""
    SELECT replaceOne(replaceOne(create_table_query, concat({db_src:String}, '.', {tbl_src:String}), concat({db_dst:String}, '.', {tbl_dst:String})), 'CREATE TABLE ', 'CREATE OR REPLACE TABLE ')
    FROM system.tables
    WHERE database = {db_src:String} AND name = {tbl_src:String}
    """, parameters = {'db_src' : db_src, 'tbl_src' : tbl_src, 'db_dst' : db_dst, 'tbl_dst' : tbl_dst})

    ddl_for_clone_table = result.result_rows[0][0]
    logger.info(f"ddl_for_clone_table:")
    logger.info(f"{ddl_for_clone_table}")
    client.command(ddl_for_clone_table)


#-----------------------------------------------------------------------------------------------------------------------
# Load files - Step ②: Get full path urls and row counts for all to-be-loaded files
#-----------------------------------------------------------------------------------------------------------------------
def get_file_urls_and_row_counts(url, configuration, client):
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
    """, parameters = {'url' : url, 'format' : configuration['format']})
    return result.result_rows


#-----------------------------------------------------------------------------------------------------------------------
# Load files - Step ③.Ⓐ: Load a single file in batches (because its file_row_count  > rows_per_batch)
#-----------------------------------------------------------------------------------------------------------------------
def load_file_in_batches(file_url, file_row_count, rows_per_batch, staging_tables,
                         configuration, client):
    row_start = 0
    row_end = rows_per_batch
    while row_start < file_row_count:
        command = create_batch_load_command(file_url, row_start, row_end, staging_tables[0]['db_staging'], staging_tables[0]['tbl_staging'], configuration)
        try:
            logger.debug(f"Batch loading file: {file_url}")
            logger.debug(f"Batch row block: {row_start} to {row_end}")
            logger.debug(f"Batch command: {command}")
            load_one_batch(command, staging_tables, client)
        except BatchFailedError as err:
            logger.error(f"{err=}")
            logger.error(f"Failed file: {file_url}")
            logger.error(f"Failed row block: {row_start} to {row_end}")
        row_start = row_end
        row_end = row_end + rows_per_batch


#-----------------------------------------------------------------------------------------------------------------------
# Load a single file in batches (Step ③.Ⓐ): Create the SQL load command
#-----------------------------------------------------------------------------------------------------------------------
def create_batch_load_command(file_url, row_start, row_end, db_staging, tbl_staging, configuration):
    extra_settings = {'input_format_parquet_preserve_order' : 1,
                      'parallelize_output_from_storages' : 0}

    # Handling of all optional configuration settings
    select = configuration['select'] if 'select' in configuration else '*'
    format_fragment =  f""", '{configuration['format']}'""" if 'format' in configuration else ''
    structure_fragment = f""", '{configuration['structure']}'""" if 'structure' in configuration else ''
    settings = configuration['settings'] if 'settings' in configuration else {}

    command = f"""
            INSERT INTO {db_staging}.{tbl_staging}
            SELECT {select} FROM s3('{file_url}'{format_fragment}{structure_fragment})
            WHERE rowNumberInAllBlocks() >= {row_start}
              AND rowNumberInAllBlocks()  < {row_end}
            SETTINGS {as_string({**settings, **extra_settings})}
        """
    return command


#-----------------------------------------------------------------------------------------------------------------------
# Load files - Step ③.Ⓑ: Load a single file completely in one batch (because its file_row_count  < rows_per_batch)
#-----------------------------------------------------------------------------------------------------------------------
def load_file_complete(file_url, staging_tables, configuration, client):
        command = create_complete_load_command(file_url, staging_tables[0]['db_staging'], staging_tables[0]['tbl_staging'], configuration)
        try:
            logger.debug(f"Batch loading file: {file_url}")
            logger.debug(f"Batch command: {command}")
            load_one_batch(command, staging_tables, client)
        except BatchFailedError as err:
            logger.error(f"{err=}")
            logger.error(f"Failed file: {file_url}")


#-----------------------------------------------------------------------------------------------------------------------
# Load a single file in batches (Step ③.Ⓑ): Create the SQL load command
#-----------------------------------------------------------------------------------------------------------------------
def create_complete_load_command(file_url, db_staging, tbl_staging, configuration):

    # Handling of all optional configuration settings
    select = configuration['select'] if 'select' in configuration else '*'
    format_fragment =  f""", '{configuration['format']}'""" if 'format' in configuration else ''
    structure_fragment = f""", '{configuration['structure']}'""" if 'structure' in configuration else ''
    settings_fragment = f"""SETTINGS {as_string(configuration['settings'])}""" if 'settings' in configuration else ''

    command = f"""
            INSERT INTO {db_staging}.{tbl_staging}
            SELECT {select} FROM s3('{file_url}'{format_fragment}{structure_fragment})
            {settings_fragment}
        """

    return command


#-----------------------------------------------------------------------------------------------------------------------
# Load one batch for a single file (Step ③.Ⓐ or Step ③.Ⓑ)
#-----------------------------------------------------------------------------------------------------------------------
def load_one_batch(batch_command, staging_tables, client):
    retries = 3
    attempt = 1
    while True:
        # Step ①: Drop all parts from all staging tables
        for d in staging_tables:
            client.command(f"TRUNCATE TABLE {d['db_staging']}.{d['tbl_staging']}")
        try:
            # Step ②: load one batch
            client.command(batch_command)
            # Step ③: copy parts (of all partitions) from all staging tables to their corresponding destination tables
            for d in staging_tables:
                copy_partitions(d['db_staging'], d['tbl_staging'], d['db_dst'], d['tbl_dst'], client)
            # Success, nothing more to do here
            return
        except Exception as err:
            logger.error(f"Unexpected {err=}, {type(err)=}")
            attempt = attempt + 1
            if attempt <= retries:
                # wait a bit for transient issues to resolve
                logger.info("Going to sleep for 60s")
                time.sleep(60)
                # retry the batch
                logger.info(f"Starting attempt {attempt} of {retries}")
                continue
            else:
                # we land here in case all retries are used unsuccessfully
                raise BatchFailedError(f"Batch still failed after {retries} attempts.")


#-----------------------------------------------------------------------------------------------------------------------
#-----------------------------------------------------------------------------------------------------------------------
# Staging tables
#-----------------------------------------------------------------------------------------------------------------------
#-----------------------------------------------------------------------------------------------------------------------


#-----------------------------------------------------------------------------------------------------------------------
# Create all staging tables - one for the main target table, and one for each MV target table, we also clone all MVs
#-----------------------------------------------------------------------------------------------------------------------
def create_staging_tables(db_dst, tbl_dst, client):
    staging_tables = []
    db_staging = db_dst
    tbl_staging = tbl_dst + '_staging'
    # create staging table for main target table
    create_tbl_clone(db_dst, tbl_dst, db_staging, tbl_staging, client)
    staging_tables.append({
        'db_staging' : db_staging, 'tbl_staging' : tbl_staging,
        'db_dst' :     db_dst, 'tbl_dst' :         tbl_dst})
    # get infos about all MVs connected to the main target table
    mvs = get_mvs(db_dst, tbl_dst, client)
    for d in  mvs:
        # MV infos
        db_mv = d['db_mv']
        mv = d['mv']
        db_mv_staging = db_mv
        mv_staging = mv + '_staging'

         # target table infos
        db_tgt = d['db_target']
        tbl_tgt = d['tbl_target']
        db_tgt_staging = db_tgt
        tbl_tgt_staging = tbl_tgt + '_staging'

        # create staging table for MV target table
        create_tbl_clone(db_tgt, tbl_tgt, db_tgt_staging, tbl_tgt_staging, client)
        # create MV clone - with staging table for main target table as source table
        #                   and staging table for original target table as target table
        create_mv_clone(
            mv_infos =      {'db_mv' :        db_mv,              'mv' :        mv,
                             'db_mv_clone' :  db_mv_staging, 'mv_clone':        mv_staging},
            tbl_src_infos = {'db_src' :       db_dst,           'tbl_src' :     tbl_dst,
                             'db_src_clone' : db_staging, 'tbl_src_clone' :     tbl_staging},
            tbl_tgt_infos = {'db_tgt' :       db_tgt,               'tbl_tgt' : tbl_tgt,
                             'db_tgt_clone' : db_tgt_staging, 'tbl_tgt_clone' : tbl_tgt_staging},
            client = client)
        staging_tables.append({
            'db_mv'         : db_mv,                  'mv' :  mv,
            'db_mv_staging' : db_mv_staging , 'mv_staging' :  mv_staging,
            'db_staging' :    db_tgt_staging, 'tbl_staging' : tbl_tgt_staging,
            'db_dst' :        db_tgt,             'tbl_dst' : tbl_tgt})

    return staging_tables


#-----------------------------------------------------------------------------------------------------------------------
#-----------------------------------------------------------------------------------------------------------------------
# Cloning MVs
#-----------------------------------------------------------------------------------------------------------------------
#-----------------------------------------------------------------------------------------------------------------------


#-----------------------------------------------------------------------------------------------------------------------
# Fetch infos about all MVs connected to main target table
#-----------------------------------------------------------------------------------------------------------------------
def get_mvs(db_dst, tbl_dst, client):
    mvs = []
    result = client.query("""
        SELECT
               mvs.1 as db,
               mvs.2 as table
        FROM (
            SELECT arrayZip(dependencies_database, dependencies_table) as mvs
            FROM system.tables
            WHERE database = {db_dst:String} AND table = {tbl_dst:String}
             )
        ARRAY JOIN mvs as mvs""", parameters = {'db_dst' : db_dst, 'tbl_dst' : tbl_dst})
    for row in result.result_rows:
        db_mv = row[0]
        mv = row[1]
        (db_target, tbl_target) = get_mv_target_table(db_mv, mv, client)
        mvs.append({'db_mv':db_mv, 'mv':mv, 'db_target':db_target, 'tbl_target': tbl_target})
    return mvs


#-----------------------------------------------------------------------------------------------------------------------
# db name and table name of a MV's target table
#-----------------------------------------------------------------------------------------------------------------------
def get_mv_target_table(db, mv, client):
    result = client.query("""
        SELECT target_db, target_table
        FROM (
            SELECT
                create_table_query,
                splitByString(' ', splitByString(' TO ', splitByString('CREATE MATERIALIZED VIEW ', create_table_query)[2])[2])[1] AS target_db_and_table,
                splitByChar('.', target_db_and_table)[1] AS target_db,
                replaceOne(target_db_and_table, target_db || '.', '') AS target_table
            FROM system.tables
            WHERE database = {db:String} AND table = {mv:String})""", parameters = {'db' : db, 'mv' : mv})
    return (result.result_rows[0][0], result.result_rows[0][1])


#-----------------------------------------------------------------------------------------------------------------------
# create MV clone - with new source table and new target table instead of original source table and target table
#-----------------------------------------------------------------------------------------------------------------------
def create_mv_clone(mv_infos, tbl_src_infos, tbl_tgt_infos, client):

    # drop staging mv in case a previous run got stopped before cleanup
    try:
        client.command(f"DROP VIEW {mv_infos['db_mv_clone']}.{mv_infos['mv_clone']}")
    except Exception as err:
        if not f"{err=}".find(" does not exist.") > -1:
            raise

    result = client.query("""
        SELECT
        replaceOne(
               replaceOne(
                   replaceOne(
                       create_table_query,
                       {db_mv:String} || '.' || {mv:String} || ' ',
                       {db_mv_clone:String} || '.' || {mv_clone:String} || ' '),
                    {db_tgt:String} || '.' || {tbl_tgt:String} || ' ',
                    {db_tgt_clone:String} || '.' || {tbl_tgt_clone:String} || ' '),
               ' FROM ' || {db_src:String} || '.' || {tbl_src:String} || ' ',
               ' FROM ' || {db_src_clone:String} || '.' || {tbl_src_clone:String} || ' ')  AS DDL
        FROM system.tables
        WHERE database = {db_mv:String} AND table = {mv:String}
    """, parameters = {
        'db_mv':mv_infos['db_mv'], 'mv':mv_infos['mv'], 'db_mv_clone':mv_infos['db_mv_clone'], 'mv_clone':mv_infos['mv_clone'],
        'db_src':tbl_src_infos['db_src'], 'tbl_src':tbl_src_infos['tbl_src'], 'db_src_clone':tbl_src_infos['db_src_clone'], 'tbl_src_clone':tbl_src_infos['tbl_src_clone'],
        'db_tgt':tbl_tgt_infos['db_tgt'], 'tbl_tgt':tbl_tgt_infos['tbl_tgt'], 'db_tgt_clone':tbl_tgt_infos['db_tgt_clone'], 'tbl_tgt_clone':tbl_tgt_infos['tbl_tgt_clone']})

    ddl_for_clone_mv = result.result_rows[0][0]
    logger.info(f"ddl_for_clone_mv:")
    logger.info(f"{ddl_for_clone_mv}")

    client.command(ddl_for_clone_mv)


#-----------------------------------------------------------------------------------------------------------------------
#-----------------------------------------------------------------------------------------------------------------------
# Copying all existing parts (for all partitions) from one table to another
#-----------------------------------------------------------------------------------------------------------------------
#-----------------------------------------------------------------------------------------------------------------------


#-----------------------------------------------------------------------------------------------------------------------
# Copy all existing parts (for all partitions) from one table to another
#-----------------------------------------------------------------------------------------------------------------------
def copy_partitions(db_src, tbl_src, db_dst, tbl_dst, client):
    partition_ids = get_partition_ids(db_src, tbl_src, client)
    for [partition_id] in partition_ids:
        logger.debug(f"Copy partition: {partition_id}")
        copy_partition(partition_id, db_src, tbl_src, db_dst, tbl_dst, client)


#-----------------------------------------------------------------------------------------------------------------------
# Get names of all existing partitions for a table
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
# Copy a single partition from one table to another
#-----------------------------------------------------------------------------------------------------------------------
def copy_partition(partition_id, db_src, tbl_src, db_dst, tbl_dst, client):
    command = f"""
        ALTER TABLE {db_dst}.{tbl_dst}
        ATTACH PARTITION {partition_id}
        FROM {db_src}.{tbl_src}"""
    client.command(command)


#-----------------------------------------------------------------------------------------------------------------------
#-----------------------------------------------------------------------------------------------------------------------
# Misc helper functions
#-----------------------------------------------------------------------------------------------------------------------
#-----------------------------------------------------------------------------------------------------------------------


#-----------------------------------------------------------------------------------------------------------------------
# transform dictionary items into comma-separated settings-fragment for SQL SETTINGS clause
# {'a' : 23, 'b' : 42} -> "'a' = 23, 'b' = 42"
#-----------------------------------------------------------------------------------------------------------------------
def as_string(settings):
    settings_string = ''
    for key in settings:
        settings_string += str(key) + ' = ' + str(settings[key]) + ', '
    return settings_string[:-2]


#-----------------------------------------------------------------------------------------------------------------------
# Drop a table
#-----------------------------------------------------------------------------------------------------------------------
def drop_staging_tables(staging_tables, client):
    for d in staging_tables:
        if 'mv_staging' in d:
            # drop a mv clone
            client.command(f"""DROP VIEW IF EXISTS {d['db_mv_staging']}.{d['mv_staging']}""")
        # drop a staging table
        client.command(f"""DROP TABLE IF EXISTS {d['db_staging']}.{d['tbl_staging']}""")


#-----------------------------------------------------------------------------------------------------------------------
# Our dedicated exception for indicating that a batch failed even after a few retries
#-----------------------------------------------------------------------------------------------------------------------
class BatchFailedError(Exception):
    pass



main()





