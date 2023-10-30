#!/usr/bin/python
import argparse
import clickhouse_connect
from clickhouse_connect import common
from datetime import datetime
import logging
import random
from retry import retry
import signal
import sys
import time
import uuid


MIN_PYTHON = (3, 10)
if sys.version_info < MIN_PYTHON:
    sys.exit("Python %s.%s or later is required.\n" % MIN_PYTHON)


# -----------------------------------------------------------------------------------------------------------------------
# Retries Configuration
# -----------------------------------------------------------------------------------------------------------------------
retry_tries = 10
retry_delay = 60
retry_backoff = 1.5


# -----------------------------------------------------------------------------------------------------------------------
# Logger Configuration
# -----------------------------------------------------------------------------------------------------------------------
def get_logger(
        LOG_FORMAT     = '%(asctime)s %(levelname)-8s %(message)s',
        LOG_NAME       = '',
        LOG_FILE_INFO  = 'file.log',
        LOG_FILE_ERROR = 'file.err'):

    logger        = logging.getLogger(LOG_NAME)
    log_formatter = logging.Formatter(LOG_FORMAT)

    # comment this to suppress console output
    stream_handler = logging.StreamHandler()
    stream_handler.setFormatter(log_formatter)
    logger.addHandler(stream_handler)

    file_handler_info = logging.FileHandler(LOG_FILE_INFO, mode='w')
    file_handler_info.setFormatter(log_formatter)
    file_handler_info.setLevel(logging.INFO)
    logger.addHandler(file_handler_info)

    file_handler_error = logging.FileHandler(LOG_FILE_ERROR, mode='w')
    file_handler_error.setFormatter(log_formatter)
    file_handler_error.setLevel(logging.WARNING)
    logger.addHandler(file_handler_error)

    # consoleHandler = logging.StreamHandler()
    # consoleHandler.setFormatter(log_formatter)
    # logger.addHandler(consoleHandler)

    logger.setLevel(logging.DEBUG)

    return logger


logger = get_logger()


# -----------------------------------------------------------------------------------------------------------------------
# Command line arguments parsing
# -----------------------------------------------------------------------------------------------------------------------
ap = argparse.ArgumentParser()

# ① ClickHouse connection settings ------------------------------------------------------------------------------------
ap.add_argument("--host", required=True)
ap.add_argument("--port", required=True)
ap.add_argument("--username", required=True)
ap.add_argument("--password", required=True)


# ② Data loading - main settings --------------------------------------------------------------------------------------
ap.add_argument("--task_database", required=True)
ap.add_argument("--task_table", required=True)
ap.add_argument("--worker_id", required=False, default=str(uuid.uuid1()).replace('-', '_'))

ap.add_argument("--database", required=True,
                help='Name of the target ClickHouse database.')
ap.add_argument("--table", required=True,
                help='Name of the target ClickHouse table.')


# ③ Data loading - optional settings ----------------------------------------------------------------------------------
ap.add_argument("--cfg.function", required=False, default='s3',
                help='Name of the table function for accessing the to-be-loaded files.')

ap.add_argument("--cfg.bucket_access_key", required=False)
ap.add_argument("--cfg.bucket_access_secret", required=False)

ap.add_argument("--cfg.format", required=False,
                help='Name of the file format used.')

ap.add_argument("--cfg.structure", required=False,
                help='Structure of the file data.')

ap.add_argument("--cfg.select", required=False, default='SELECT *',
                help='Custom SELECT clause for retrieving the file data.')

ap.add_argument("--cfg.where", required=False, default='',
                help='Custom WHERE clause for retrieving the file data.')

ap.add_argument('--cfg.query_settings', nargs='+', default=[], required=False,
                help='Custom query-level settings.')

args = vars(ap.parse_args())


# staging_tables is global for the signal_handler
staging_tables = []


# -----------------------------------------------------------------------------------------------------------------------
# as the worker executes a endless loop with sleep breaks,
# we use a signal handler for cleaning up all staging tables
# when the script is stopped via Ctrl+C
# -----------------------------------------------------------------------------------------------------------------------
def signal_handler(sig, frame):
    # logger.info(f"You pressed Ctrl+C!")
    logger.info(f"Cleanup: Drop all staging tables (and MV clones)")

    # As this runs in another thread (compared to the main thread) we need a different
    # client with a different session id - otherwise ClickHouse will complain
    client = clickhouse_connect.get_client(
    host=args['host'],
    port=args['port'],
    username=args['username'],
    password=args['password'],
    secure=True
    # ,session_id=args['worker_id'] + '_cleanup'
    )

    drop_staging_tables(staging_tables, client)

    sys.exit(0)

signal.signal(signal.SIGINT, signal_handler)


# -----------------------------------------------------------------------------------------------------------------------
# Calling the main entry point
# -----------------------------------------------------------------------------------------------------------------------
def main():

    # disable session ids
    # In this case ClickHouse Connect will not send any session id, and a random session id will be generated by the
    # ClickHouse server. Temporary tables and session level settings will not be available.
    common.set_setting('autogenerate_session_id', False)

    client = clickhouse_connect.get_client(
        host=args['host'],
        port=args['port'],
        username=args['username'],
        password=args['password'],
        secure=True,
        # session_id=args['worker_id'],
        settings={
            'keeper_map_strict_mode': 1
        })

    configuration = to_configuration_dictionary(args)

    # Create all necessary staging tables (and MV clones)
    logger.info(f"Creating staging tables")
    global staging_tables
    staging_tables = create_staging_tables(db_dst=args['database'], tbl_dst=args['table'], client=client, configuration=configuration)
    logger.info(f"Done")

    # Start the worker process
    worker_process(
        db_dst=args['database'],
        tbl_dst=args['table'],
        client=client,
        worker_id = args['worker_id'],
        sleep_time = 60,
        configuration=configuration)


# -----------------------------------------------------------------------------------------------------------------------
# -----------------------------------------------------------------------------------------------------------------------
# Worker process
# -----------------------------------------------------------------------------------------------------------------------
# -----------------------------------------------------------------------------------------------------------------------


# -----------------------------------------------------------------------------------------------------------------------
# The worker process main entry point
# -----------------------------------------------------------------------------------------------------------------------
def worker_process(db_dst, tbl_dst, worker_id,  sleep_time, client, configuration={}):
    logger.info(f'starting worker {worker_id}')

    while True:

        logger.info(f'---------- polling a chunk of files')
        claimed_files = claim_files(args['task_database'], args['task_table'], worker_id, 10, client)

        if claimed_files is not None:
            logger.info(f'Polled a chunk of {len(claimed_files)} files')
            load_files_atomically(claimed_files, staging_tables, configuration, client)
            cleanup_files(args['task_database'], args['task_table'], claimed_files, client)
        else:
            logger.info(f'Poll was unsuccessful')
            logger.info(f'{worker_id} is sleeping 60s till next poll')
            time.sleep(sleep_time)


# -----------------------------------------------------------------------------------------------------------------------
# Claim a chunk of files from the task table
# -----------------------------------------------------------------------------------------------------------------------
def claim_files(task_database, task_table, worker_id, retries, client):
    jobs = _query_rows(client, f"SELECT file_path, file_paths FROM {task_database}.{task_table} WHERE worker_id = '' ORDER BY scheduled ASC LIMIT {retries}")

    for job in jobs:
        file_path = job[0]
        logger.info(f'attempting to claim {file_path}')
        scheduled_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        try:
            # keeper map doesn't allow two threads to set here
            _query_row(client, f"ALTER TABLE {task_database}.{task_table} UPDATE worker_id = '{worker_id}', "
                              f"started_time = '{scheduled_time}' WHERE file_path = '{file_path}' AND worker_id = ''")
            # this may either throw an exception if another worker gets there first OR return 0 rows if the
            # job has already been processed and deleted or claimed successfully. So we check we have set and claimed.
            assigned_worker_id = _query_row(client, f"SELECT worker_id FROM {task_database}.{task_table} WHERE file_path = '{file_path}'")
            if assigned_worker_id[0] == worker_id:
                logger.info(f'[{worker_id}] claimed file [{file_path}]')
                return job[1]
            else:
                logger.info(f'unable to claim file [{file_path}]. maybe already claimed.')
        except:
            logger.exception(f'unable to claim file [{file_path}]. maybe already claimed.')
    return None


# -----------------------------------------------------------------------------------------------------------------------
# After processing a chunk of files from the work_queue, we delete the corresponding task from the task table
# -----------------------------------------------------------------------------------------------------------------------
def cleanup_files(task_database, task_table, claimed_files, client):

    try:
        logger.info(f'cleaning up job [{claimed_files[0]}]')
        # always release the job so it can be scheduled
        _command(client, f"DELETE FROM {task_database}.{task_table} WHERE file_path='{claimed_files[0]}'")
    except:
        logger.exception(f'unable to clean up job [{file_path}]. Manually clean.')


# -----------------------------------------------------------------------------------------------------------------------
# -----------------------------------------------------------------------------------------------------------------------
# Loading a chunk of files atomically (all or nothing) into the target table + all existing MVs
# -----------------------------------------------------------------------------------------------------------------------
# -----------------------------------------------------------------------------------------------------------------------


# -----------------------------------------------------------------------------------------------------------------------
# The main entry point for loading a chunk of files atomically
# -----------------------------------------------------------------------------------------------------------------------
@retry(tries=retry_tries, delay=retry_delay, backoff=retry_backoff, logger=logger)
def load_files_atomically(file_list, staging_tables, configuration, client):

    logger.info(f"staging load started")
    try:
        _load_files(file_list, staging_tables, configuration, client)
    except Exception as err:
        try:
            truncate_tables(staging_tables, client)
        except Error as err:
            # if all retries are exceeded, stop the worker as we have a unrecoverable state
            sys.exit(f"Unable to truncate tables for files chunk with key file: {file_list[0]}")
        raise
    logger.info(f"staging load complete")

    logger.info(f"moving partitions from staging tables to target tables")
    for d in staging_tables:
        move_partitions(d['db_staging'], d['tbl_staging'], d['db_dst'], d['tbl_dst'], client)


# -----------------------------------------------------------------------------------------------------------------------
# Helper function
# -----------------------------------------------------------------------------------------------------------------------
def _load_files(file_list, staging_tables, configuration, client):
    file_number = len(file_list)
    current_number = 1

    for file_url in file_list:
        logger.info(f"Loading file {current_number} of {file_number} into staging tables: {file_url}")

        command = create_batch_load_command(file_url, staging_tables[0]['db_staging'], staging_tables[0]['tbl_staging'],
                                        configuration)

        print(command)
        client.command(command)
        current_number+=1


# -----------------------------------------------------------------------------------------------------------------------
# Construction of the batch load SQL command
# -----------------------------------------------------------------------------------------------------------------------
def create_batch_load_command(file_url, db_staging, tbl_staging, configuration):
    # Handling of all optional configuration settings
    query_clause_fragments = to_query_clause_fragments(configuration)

    command = f"""
            INSERT INTO {db_staging}.{tbl_staging}
            {query_clause_fragments['select_fragment']} FROM {query_clause_fragments['function_fragment']}'{file_url}'{query_clause_fragments['access_fragment']}{query_clause_fragments['format_fragment']}{query_clause_fragments['structure_fragment']})
            {query_clause_fragments['filter_fragment']}
            {query_clause_fragments['settings_fragment']}
        """

    return command


# -----------------------------------------------------------------------------------------------------------------------
# Turn optional query configuration settings into fragments for the query clauses
# -----------------------------------------------------------------------------------------------------------------------
def to_query_clause_fragments(configuration):

    access_fragment = ''
    if 'bucket_access_key' in configuration:
        access_fragment = f""", '{configuration['bucket_access_key']}', '{configuration['bucket_access_secret']}'"""

    filter_fragment = ''
    if 'where' in configuration:
        filter_fragment = configuration['where']

        settings = {}
    if 'settings' in configuration:
        settings = {**settings, **configuration['settings']}

    return {
        'function_fragment': f"""{configuration['function']}(""",
        'access_fragment': access_fragment,
        'select_fragment': f"""{configuration['select']} """,
        'format_fragment': f""", '{configuration['format']}'""" if 'format' in configuration else '',
        'structure_fragment': f""", '{configuration['structure']}'""" if 'structure' in configuration else '',
        'filter_fragment': filter_fragment,
        'settings_fragment': f"""SETTINGS {to_string(settings)}""" if len(settings) > 0 else ''}


# -----------------------------------------------------------------------------------------------------------------------
# Transform dictionary items into comma-separated settings-fragment for SQL SETTINGS clause
# {'a' : 23, 'b' : 42} -> "'a' = 23, 'b' = 42"
# -----------------------------------------------------------------------------------------------------------------------
def to_string(settings):
    settings_string = ''
    for key in settings:
        settings_string += str(key) + ' = ' + str(settings[key]) + ', '
    return settings_string[:-2]


# -----------------------------------------------------------------------------------------------------------------------
# We truncate all staging tables in case something goes wrong and retry the load
# -----------------------------------------------------------------------------------------------------------------------
def truncate_tables(staging_tables, client):
    for d in staging_tables:
        _command(client, f"TRUNCATE TABLE {d['db_staging']}.{d['tbl_staging']}")


# -----------------------------------------------------------------------------------------------------------------------
# -----------------------------------------------------------------------------------------------------------------------
# Retries of ClickHouse commands and queries
# -----------------------------------------------------------------------------------------------------------------------
# -----------------------------------------------------------------------------------------------------------------------


@retry(tries=retry_tries, delay=retry_delay, backoff=retry_backoff, logger=logger)
def _command(client, command):
    logger.debug(f"{command}")
    client.command(command)

@retry(tries=retry_tries, delay=retry_delay, backoff=retry_backoff, logger=logger)
def _query(client, query, parameters = None):
    result = client.query(query, parameters)
    return result

@retry(tries=retry_tries, delay=retry_delay, backoff=retry_backoff, logger=logger)
def _query_rows(client, query):
    return client.query(query).result_set

@retry(tries=retry_tries, delay=retry_delay, backoff=retry_backoff, logger=logger)
def _query_row(client, query):
    for result in client.query(query).result_set:
        return result
    return None


# -----------------------------------------------------------------------------------------------------------------------
# -----------------------------------------------------------------------------------------------------------------------
# Staging tables
# -----------------------------------------------------------------------------------------------------------------------
# -----------------------------------------------------------------------------------------------------------------------


# -----------------------------------------------------------------------------------------------------------------------
# Create all staging tables - one for the main target table, and one for each MV target table, we also clone all MVs
# -----------------------------------------------------------------------------------------------------------------------
def create_staging_tables(db_dst, tbl_dst, client, configuration):
    staging_tables = []

    db_staging = db_dst + configuration['staging_suffix']
    create_staging_db(db_staging, client)

    tbl_staging = tbl_dst
    # create staging table for main target table
    create_tbl_clone(db_dst, tbl_dst, db_staging, tbl_staging, client)
    staging_tables.append({
        'db_staging': db_staging, 'tbl_staging': tbl_staging,
        'db_dst': db_dst, 'tbl_dst': tbl_dst})
    # get infos about all MVs connected to the main target table
    mvs = get_mvs(db_dst, tbl_dst, client)
    for d in mvs:
        # MV infos
        db_mv = d['db_mv']
        mv = d['mv']
        db_mv_staging = db_mv + configuration['staging_suffix']
        mv_staging = mv

        # target table infos
        db_tgt = d['db_target']
        tbl_tgt = d['tbl_target']
        db_tgt_staging = db_tgt + configuration['staging_suffix']
        tbl_tgt_staging = tbl_tgt

        # create staging table for MV target table
        create_tbl_clone(db_tgt, tbl_tgt, db_tgt_staging, tbl_tgt_staging, client)
        # create MV clone - with staging table for main target table as source table
        #                   and staging table for original target table as target table
        create_mv_clone(
            mv_infos={'db_mv': db_mv, 'mv': mv,
                      'db_mv_clone': db_mv_staging, 'mv_clone': mv_staging},
            tbl_src_infos={'db_src': db_dst, 'tbl_src': tbl_dst,
                           'db_src_clone': db_staging, 'tbl_src_clone': tbl_staging},
            tbl_tgt_infos={'db_tgt': db_tgt, 'tbl_tgt': tbl_tgt,
                           'db_tgt_clone': db_tgt_staging, 'tbl_tgt_clone': tbl_tgt_staging},
            client=client)
        staging_tables.append({
            'db_mv': db_mv, 'mv': mv,
            'db_mv_staging': db_mv_staging, 'mv_staging': mv_staging,
            'db_staging': db_tgt_staging, 'tbl_staging': tbl_tgt_staging,
            'db_dst': db_tgt, 'tbl_dst': tbl_tgt})

    return staging_tables


# -----------------------------------------------------------------------------------------------------------------------
# Clone a table
# -----------------------------------------------------------------------------------------------------------------------
def create_tbl_clone(db_src, tbl_src, db_dst, tbl_dst, client):
    command = f"""
        CREATE OR REPLACE TABLE {db_dst}.{tbl_dst} AS {db_src}.{tbl_src}
        """
    _command(client, command)


# -----------------------------------------------------------------------------------------------------------------------
# Create the staging database
# -----------------------------------------------------------------------------------------------------------------------
def create_staging_db(db_dst, client):
    command = f"""
        CREATE DATABASE IF NOT EXISTS {db_dst}
        """
    _command(client, command)


# -----------------------------------------------------------------------------------------------------------------------
# Drop all staging tables, including MV clones
# -----------------------------------------------------------------------------------------------------------------------
def drop_staging_tables(staging_tables, client):
    _command(client, f"""DROP DATABASE IF EXISTS {staging_tables[0]['db_staging']}""")

    # for d in staging_tables:
    #     if 'mv_staging' in d:
    #         # drop a mv clone
    #         _command(client, f"""DROP VIEW IF EXISTS {d['db_mv_staging']}.{d['mv_staging']}""")
    #     # drop a staging table
    #     _command(client, f"""DROP TABLE IF EXISTS {d['db_staging']}.{d['tbl_staging']}""")


# -----------------------------------------------------------------------------------------------------------------------
# -----------------------------------------------------------------------------------------------------------------------
# Cloning MVs
# -----------------------------------------------------------------------------------------------------------------------
# -----------------------------------------------------------------------------------------------------------------------


# -----------------------------------------------------------------------------------------------------------------------
# Fetch infos about all MVs connected to main target table
# -----------------------------------------------------------------------------------------------------------------------
def get_mvs(db_dst, tbl_dst, client):
    mvs = []
    result = _query(client, """
        SELECT
               mvs.1 as db,
               mvs.2 as table
        FROM (
            SELECT arrayZip(dependencies_database, dependencies_table) as mvs
            FROM system.tables
            WHERE database = {db_dst:String} AND table = {tbl_dst:String}
             )
        ARRAY JOIN mvs as mvs""", parameters={'db_dst': db_dst, 'tbl_dst': tbl_dst})
    for row in result.result_rows:
        db_mv = row[0]
        mv = row[1]
        (db_target, tbl_target) = get_mv_target_table(db_mv, mv, client)
        mvs.append({'db_mv': db_mv, 'mv': mv, 'db_target': db_target, 'tbl_target': tbl_target})
    return mvs


# -----------------------------------------------------------------------------------------------------------------------
# Get db name and table name of a MV's target table
# -----------------------------------------------------------------------------------------------------------------------
def get_mv_target_table(db, mv, client):
    result = _query(client, """
        SELECT target_db, target_table
        FROM (
            SELECT
                create_table_query,
                splitByString(' ', splitByString(' TO ', splitByString('CREATE MATERIALIZED VIEW ', create_table_query)[2])[2])[1] AS target_db_and_table,
                splitByChar('.', target_db_and_table)[1] AS target_db,
                replaceOne(target_db_and_table, target_db || '.', '') AS target_table
            FROM system.tables
            WHERE database = {db:String} AND table = {mv:String})""", parameters={'db': db, 'mv': mv})
    return (result.result_rows[0][0], result.result_rows[0][1])


# -----------------------------------------------------------------------------------------------------------------------
# Create MV clone - with new source table and new target table instead of original source table and target table
# -----------------------------------------------------------------------------------------------------------------------
def create_mv_clone(mv_infos, tbl_src_infos, tbl_tgt_infos, client):
    # drop staging mv in case a previous run got stopped before cleanup
    _command(client, f"DROP VIEW IF EXISTS {mv_infos['db_mv_clone']}.{mv_infos['mv_clone']}")

    result = _query(client, """
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
    """, parameters={
        'db_mv': mv_infos['db_mv'], 'mv': mv_infos['mv'], 'db_mv_clone': mv_infos['db_mv_clone'],
        'mv_clone': mv_infos['mv_clone'],
        'db_src': tbl_src_infos['db_src'], 'tbl_src': tbl_src_infos['tbl_src'],
        'db_src_clone': tbl_src_infos['db_src_clone'], 'tbl_src_clone': tbl_src_infos['tbl_src_clone'],
        'db_tgt': tbl_tgt_infos['db_tgt'], 'tbl_tgt': tbl_tgt_infos['tbl_tgt'],
        'db_tgt_clone': tbl_tgt_infos['db_tgt_clone'], 'tbl_tgt_clone': tbl_tgt_infos['tbl_tgt_clone']})

    ddl_for_clone_mv = result.result_rows[0][0]
    logger.info(f"ddl_for_clone_mv:")
    logger.info(f"{ddl_for_clone_mv}")

    _command(client, ddl_for_clone_mv)


# -----------------------------------------------------------------------------------------------------------------------
# -----------------------------------------------------------------------------------------------------------------------
# Copying parts from one table to another
# -----------------------------------------------------------------------------------------------------------------------
# -----------------------------------------------------------------------------------------------------------------------


# -----------------------------------------------------------------------------------------------------------------------
# Move all existing parts (for all partitions) from one table to another
# -----------------------------------------------------------------------------------------------------------------------
def move_partitions(db_src, tbl_src, db_dst, tbl_dst, client):
    logger.info(f"moving partitions for {db_src}.{tbl_src} to {db_dst}.{tbl_dst}")
    partition_ids = get_partition_ids(db_src, tbl_src, client)
    for [partition_id] in partition_ids:
        logger.info(f"Move partition: {partition_id}")
        move_partition(partition_id, db_src, tbl_src, db_dst, tbl_dst, client)


# -----------------------------------------------------------------------------------------------------------------------
# Get names of all existing partitions for a table
# -----------------------------------------------------------------------------------------------------------------------
def get_partition_ids(db, table, client):
    result = _query(client, """
        SELECT partition
        FROM system.parts
        WHERE database = {db:String}
          AND table = {table:String}
        GROUP BY partition
        ORDER BY partition
    """, parameters={'db': db, 'table': table})
    return result.result_rows


# -----------------------------------------------------------------------------------------------------------------------
# Move a single partition from one table to another
# -----------------------------------------------------------------------------------------------------------------------
def move_partition(partition_id, db_src, tbl_src, db_dst, tbl_dst, client):
    command = f"""
        ALTER TABLE {db_src}.{tbl_src}
        MOVE PARTITION {partition_id}
        TO TABLE {db_dst}.{tbl_dst}"""
    _command(client, command)


# -----------------------------------------------------------------------------------------------------------------------
# -----------------------------------------------------------------------------------------------------------------------
# Command line argument handling
# -----------------------------------------------------------------------------------------------------------------------
# -----------------------------------------------------------------------------------------------------------------------


def to_configuration_dictionary(args):
    configuration = {}
    add_to_dictionary_if_present(configuration, args, 'cfg.function', 'function')
    add_to_dictionary_if_present(configuration, args, 'cfg.bucket_access_key', 'bucket_access_key')
    add_to_dictionary_if_present(configuration, args, 'cfg.bucket_access_secret', 'bucket_access_secret')
    add_to_dictionary_if_present(configuration, args, 'cfg.format', 'format')
    add_to_dictionary_if_present(configuration, args, 'cfg.structure', 'structure')
    add_to_dictionary_if_present(configuration, args, 'cfg.select', 'select')
    add_to_dictionary_if_present(configuration, args, 'cfg.where', 'where')

    configuration.update({'staging_suffix': '_' + args['worker_id']})

    configuration.update({'settings': to_query_settings_dictionary(args)})

    return configuration


def add_to_dictionary_if_present(dictionary, args, argument, key):
    if args[argument] != None:
        dictionary.update({key: args[argument]})


def to_query_settings_dictionary(args):
    query_settings = {}
    if len(args['cfg.query_settings']) > 0:
        for s in args['cfg.query_settings']:
            s_split = s.split('=')
            query_settings.update({s_split[0]: s_split[1]})
    return query_settings


# -----------------------------------------------------------------------------------------------------------------------
# -----------------------------------------------------------------------------------------------------------------------
# Calling the main function
# -----------------------------------------------------------------------------------------------------------------------
# -----------------------------------------------------------------------------------------------------------------------
main()