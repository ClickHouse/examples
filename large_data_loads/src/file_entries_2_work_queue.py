#!/usr/bin/python
import argparse
import clickhouse_connect
import logging
import random
from retry import retry
import sys
import time


MIN_PYTHON = (3, 10)
if sys.version_info < MIN_PYTHON:
    sys.exit("Python %s.%s or later is required.\n" % MIN_PYTHON)

# -----------------------------------------------------------------------------------------------------------------------
# Retries Configuration
# -----------------------------------------------------------------------------------------------------------------------
retry_tries = 6
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

ap.add_argument("--file", required=True)
ap.add_argument("--task_database", required=True)
ap.add_argument("--task_table", required=True)
ap.add_argument("--files_chunk_size_min", required=False, default=500,
                help='How many files are atomically processed together at a minimum.')
ap.add_argument("--files_chunk_size_max", required=False, default=1000,
                help='How many files are atomically processed together at a maximum.')

args = vars(ap.parse_args())


# -----------------------------------------------------------------------------------------------------------------------
# Calling the main entry point
# -----------------------------------------------------------------------------------------------------------------------
def main():
    client = clickhouse_connect.get_client(
        host=args['host'],
        port=args['port'],
        username=args['username'],
        password=args['password'],
        secure=True
    )

    # Get full path urls for all to-be-loaded files
    logger.info(f"Fetching all files")
    file_url_list = get_file_urls_from_file(args['file'])
    logger.debug(f"Number of files: {len(file_url_list)}")
    file_url_list = file_url_list[:500000]
    logger.debug(f"Number of files: {len(file_url_list)}")

    # create the full set of rows for the task table
    data_array = to_data_array(file_url_list, int(args['files_chunk_size_min']), int(args['files_chunk_size_max']))

    # In order to reduce the number of insert queries, we create batches of 500 rows for the task table per insert
    for sub_list in chunker(data_array, 500):
        # insert the batch of rows into the task table
        _insert(client, args['task_database'], args['task_table'], sub_list, ['file_path', 'file_paths'])


# -----------------------------------------------------------------------------------------------------------------------
# We create rows for the task table here.
# Each row looks like this:
# [first_file, [first_file, second_file, third_file, ...]]
# - the first row column is used as the key in the task table
# - the second row column contains the chunk of files (number of files per chunk is randomized) that will be loaded
#   atomically by a worker
#
# This data layout allows a much more efficient assignment of file chunks to workers, compared to storing a single file
# per task table row - as a worker uses 'atomic updates' (via keeper_map_strict_mode) to claim a row from the task table,
# claiming 100s of files in order to process a chunk of files atomically would take much more time as 'atomic updates'
# come with a cost
# -----------------------------------------------------------------------------------------------------------------------
def to_data_array(file_url_list, files_chunk_size_min, files_chunk_size_max):
    data = []
    i_start = 0
    while i_start < len(file_url_list):
        # In order to prevent contention on Keeper (during the actual data loading) we randomize the files chunk size
        files_chunk_size = random.randrange(files_chunk_size_min, files_chunk_size_max)
        sub_list = file_url_list[slice(i_start, i_start+files_chunk_size)]
        key_file = sub_list[:1][0]
        data.append([key_file, sub_list])
        i_start = i_start + files_chunk_size
    return data


# -----------------------------------------------------------------------------------------------------------------------
# Load the file entries into a in-memory list
# -----------------------------------------------------------------------------------------------------------------------
def get_file_urls_from_file(file):
    file_list = []
    with open(file, 'r') as file_urls:
        for line in file_urls:
            file_list.append(line.strip())
    return file_list


# -----------------------------------------------------------------------------------------------------------------------
# Execute an insert query
# -----------------------------------------------------------------------------------------------------------------------
@retry(tries=retry_tries, delay=retry_delay, backoff=retry_backoff, logger=logger)
def _insert(client, database, table, data, column_names):
    logger.debug(f"insert(..., {table}, ..., {column_names}")
    client.insert(database=database, table=table, data=data, column_names=column_names)


# -----------------------------------------------------------------------------------------------------------------------
# Split a list into chunks
# -----------------------------------------------------------------------------------------------------------------------
def chunker(seq, size):
    return (seq[pos:pos + size] for pos in range(0, len(seq), size))


main()