"""Shared data, queries, and format settings for the local demo and recorded-run harness."""
N = 500000
FIELDS = [
    ('event_id','Int64'), ('event_time','DateTime64(3, \'UTC\')'),
    ('tenant_id','Int32'), ('user_id','Int64'), ('event_type','String'),
    ('country','String'), ('status','Int32'), ('latency_ms','Float64'),
    ('bytes_sent','Int64'), ('cpu_ms','Float64'), ('path','String'),
    ('host','String'), ('user_agent','String'), ('campaign','String'),
    ('email','String'), ('request_id','String'), ('payload','String'),
    ('region','String'), ('service','String'), ('retry_count','Int32')]
NAMES = [x[0] for x in FIELDS]
STRUCT = ', '.join(f'{n} {t}' for n,t in FIELDS)
GEN = f"""SELECT
 toInt64(number) AS event_id,
 toDateTime64('2026-01-01 00:00:00',3,'UTC') + toIntervalMillisecond(number * 137) AS event_time,
 toInt32(number % 100) AS tenant_id,
 toInt64(cityHash64(number) % 100000) AS user_id,
 ['view','click','purchase','login'][1 + number % 4] AS event_type,
 ['US','GB','DE','IN','JP'][1 + number % 5] AS country,
 toInt32(if(number % 37 = 0, 500, 200)) AS status,
 toFloat64(1 + cityHash64(number,1) % 10000) / 10 AS latency_ms,
 toInt64(cityHash64(number,2) % 100000) AS bytes_sent,
 toFloat64(cityHash64(number,3) % 10000) / 100 AS cpu_ms,
 concat('/api/products/',toString(number % 10000)) AS path,
 concat('edge-',toString(number % 50),'.example.test') AS host,
 ['Chrome-test','Firefox-test','SDK-test'][1 + number % 3] AS user_agent,
 concat('campaign-',toString(number % 30)) AS campaign,
 concat('user',toString(number % 100000),'@example.test') AS email,
 hex(sipHash128(number)) AS request_id,
 concat('{{\"product\":',toString(number % 10000),',\"trace\":\"',
 hex(sipHash128(number,11)),hex(sipHash128(number,12)),
 hex(sipHash128(number,13)),hex(sipHash128(number,14)),'\"}}') AS payload,
 ['us-east','eu-west','ap-south'][1 + number % 3] AS region,
 ['checkout','catalog','identity','search'][1 + number % 4] AS service,
 toInt32(number % 3) AS retry_count
FROM numbers({N})"""

QUERY_SETTINGS = ['--max_threads=1', '--max_memory_usage=1500000000', '--max_execution_time=30', '--max_rows_to_read=600000', '--max_bytes_to_read=1500000000', '--max_result_rows=600000', '--input_format_parallel_parsing=0', '--input_format_parquet_preserve_order=1', '--storage_file_read_method=pread', '--use_query_cache=0', '--use_parquet_metadata_cache=0', '--input_format_parquet_memory_high_watermark=536870912']
EXPORT_SETTINGS = {'Avro': ['--output_format_avro_codec=zstd', '--output_format_avro_sync_interval=65536', '--output_format_avro_string_column_pattern=.*'], 'Parquet': ['--output_format_parquet_compression_method=zstd', '--output_format_parquet_row_group_size=100000', '--output_format_parquet_row_group_size_bytes=134217728', '--output_format_parquet_data_page_size=1048576', '--output_format_parquet_parallel_encoding=0', '--output_format_parquet_write_page_index=1']}
