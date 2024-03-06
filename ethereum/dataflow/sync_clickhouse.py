import argparse
import logging
import apache_beam as beam
import clickhouse_connect
from apache_beam.options.pipeline_options import PipelineOptions
from apache_beam.options.pipeline_options import SetupOptions
from clickhouse_connect.driver.models import ColumnDef


class ClickHouse(beam.DoFn):

    def __init__(self, table, host, port, username, password, ssl):
        self._host = host
        self._port = port
        self._username = username
        self._password = password
        self._ssl = ssl
        self._table = table
        self._first = True
        self._column_names = []
        self._column_types = {}
        self._client = None

    def process(self, elements):
        batch = []
        for element in elements:
            batch.append([self._column_types[column].python_null if element[column] is None and not self._column_types[
                column].nullable else element[column] for column in self._column_names])
        self._client.insert(self._table, batch, column_names=self._column_names)

    def setup(self):
        self._client = clickhouse_connect.get_client(host=self._host, port=self._port, username=self._username,
                                                     password=self._password, secure=self._ssl)
        describe_result = self._client.query(f'DESCRIBE TABLE {self._table}')
        column_defs = [ColumnDef(**row) for row in describe_result.named_results()
                       if row['default_type'] not in ('ALIAS', 'MATERIALIZED')]
        self._column_names = [cd.name for cd in column_defs]
        self._column_types = {cd.name: cd.ch_type for cd in column_defs}

    def teardown(self):
        self._client.close()


def run(argv=None, save_main_session=True):
    parser = argparse.ArgumentParser()
    parser.add_argument(
        '--table',
        dest='table',
        default='clickhouse-cloud.crypto_ethereum.blocks',
        help='Big Query to run.')
    parser.add_argument(
        '--target_table',
        dest='target_table',
        default='blocks',
        help='Target table.')
    parser.add_argument(
        '--clickhouse_host',
        dest='clickhouse_host',
        default="localhost",
        help='ClickHouse Host.')
    parser.add_argument(
        '--clickhouse_port',
        dest='clickhouse_port',
        default=8443,
        type=int,
        help='ClickHouse Port.')
    parser.add_argument(
        '--clickhouse_no_ssl',
        dest='clickhouse_no_ssl',
        default=False,
        action='store_true',
        help='ClickHouse SSL.')
    parser.add_argument(
        '--clickhouse_username',
        dest='clickhouse_username',
        default='default',
        help='ClickHouse Username.')
    parser.add_argument(
        '--clickhouse_password',
        dest='clickhouse_password',
        default="",
        help='ClickHouse Password.')

    known_args, pipeline_args = parser.parse_known_args(argv)
    pipeline_options = PipelineOptions(pipeline_args)
    pipeline_options.view_as(SetupOptions).save_main_session = save_main_session
    with beam.Pipeline(options=pipeline_options) as pipeline:
        rows = pipeline | 'ReadTable' >> beam.io.ReadFromBigQuery(table=known_args.table)
        batches = rows | 'Group into batches' >> beam.BatchElements(min_batch_size=10000, max_batch_size=10000)
        batches | 'SendToClickHouse' >> beam.ParDo(ClickHouse(known_args.target_table, known_args.clickhouse_host,
                                                              known_args.clickhouse_port,
                                                              known_args.clickhouse_username,
                                                              known_args.clickhouse_password,
                                                              not known_args.clickhouse_no_ssl))


if __name__ == '__main__':
    logging.getLogger().setLevel(logging.INFO)
    run()
