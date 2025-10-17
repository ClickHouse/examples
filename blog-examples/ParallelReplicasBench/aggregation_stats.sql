WITH
    {pretty:String}   AS _pretty,     -- "1" = formatted, "0" = raw
    {sections:String} AS _sections,   -- "1" = show section headers, "0" = hide
    {lc:String}       AS _lc,         -- log comment

    T0 AS (
        SELECT hostName() AS host_name, *
        FROM clusterAllReplicas(default, system.query_log)
        WHERE
            log_comment = _lc
            AND query_kind = 'Select'
            AND type = 'QueryFinish'
    ),
    T1 AS (
        SELECT
            read_rows AS query_rows_read,
            result_rows AS query_rows_returned,
            query_duration_ms / 1000.0 AS query_duration_s
        FROM T0
        WHERE is_initial_query
    )
SELECT
    /* ===== Host / initiator ===== */
    regexpExtract(T0.host_name, 'server-(.*)$') AS host_id,
    T0.is_initial_query AS is_initiator_node,

    /* ===== Section: query (initiator only) ===== */
    multiIf(_sections = 1 AND T0.is_initial_query, '-------------------- query --------------------', NULL) AS section_query,

    -- Global/query-level stats (only for initiator node)
    if(T0.is_initial_query,
        multiIf(_pretty = 1, concat(formatReadableQuantity(T0.ProfileEvents['SelectedParts']), ' parts selected'), toString(T0.ProfileEvents['SelectedParts'])),
        NULL
    ) AS query_selected_parts,
    if(T0.is_initial_query,
        multiIf(_pretty = 1, concat(formatReadableQuantity(T0.ProfileEvents['SelectedRanges']), ' ranges selected'), toString(T0.ProfileEvents['SelectedRanges'])),
        NULL
    ) AS query_selected_ranges,
    if(T0.is_initial_query,
        multiIf(_pretty = 1, concat(formatReadableQuantity(T0.ProfileEvents['SelectedMarks']), ' granules selected'), toString(T0.ProfileEvents['SelectedMarks'])),
        NULL
    ) AS query_selected_granules,

    if(T0.is_initial_query,
        multiIf(
            _pretty = 1,
            concat(formatReadableSize(sum(T0.ProfileEvents['CompressedReadBufferBytes']) OVER ()), ' read'),
            toString(sum(T0.ProfileEvents['CompressedReadBufferBytes']) OVER ())
        ),
        NULL
    ) AS query_bytes_read,

    if(T0.is_initial_query,
        multiIf(_pretty = 1, concat(formatReadableQuantity(T1.query_rows_read), ' rows read'), toString(T1.query_rows_read)),
        NULL
    ) AS query_rows_read,
    if(T0.is_initial_query,
        multiIf(_pretty = 1, concat(formatReadableQuantity(T1.query_rows_returned), ' rows returned'), toString(T1.query_rows_returned)),
        NULL
    ) AS query_rows_returned,
    if(T0.is_initial_query,
        multiIf(_pretty = 1, concat(toString(round(T1.query_duration_s, 2)), ' s total'), toString(round(T1.query_duration_s, 2))),
        NULL
    ) AS query_duration_s,

    -- Global throughput (initiator only)
    if(T0.is_initial_query,
        multiIf(
            _pretty = 1,
            concat(formatReadableQuantity(round(T1.query_rows_read / nullIf(T1.query_duration_s, 0), 2)), ' rows/s total'),
            toString(round(T1.query_rows_read / nullIf(T1.query_duration_s, 0), 2))
        ),
        NULL
    ) AS query_rows_per_sec,

    if(T0.is_initial_query,
        multiIf(
            _pretty = 1,
            concat(formatReadableSize((sum(T0.ProfileEvents['CompressedReadBufferBytes']) OVER ()) / nullIf(T1.query_duration_s, 0)), '/s total'),
            toString(round((sum(T0.ProfileEvents['CompressedReadBufferBytes']) OVER ()) / nullIf(T1.query_duration_s, 0), 2))
        ),
        NULL
    ) AS query_bytes_per_sec,

    /* ===== Section: replica derived ===== */
    multiIf(_sections = 1, '--------- replica: temperature & share ---------', NULL) AS section_replica_derived,

    multiIf(
        T0.ProfileEvents['ThreadpoolReaderReadBytes'] = T0.ProfileEvents['CachedReadBufferReadFromCacheBytes'], 'hot',
        T0.ProfileEvents['CachedReadBufferReadFromCacheBytes'] = 0, 'cold',
        'warm'
    ) AS replica_temperature,

    multiIf(
        _pretty = 1,
        concat(toString(round(100 * T0.ProfileEvents['RowsReadByMainReader'] / T1.query_rows_read, 2)), '%'),
        toString(round(100 * T0.ProfileEvents['RowsReadByMainReader'] / T1.query_rows_read, 2))
    ) AS replica_percentage_processed,

    /* ===== Section: memory ===== */
    multiIf(_sections = 1, '--------------- replica: memory ---------------', NULL) AS section_replica_memory,
    multiIf(_pretty = 1, formatReadableSize(T0.memory_usage), toString(T0.memory_usage)) AS replica_memory_usage,

    /* ===== Section: throughput ===== */
    multiIf(_sections = 1, '------------- replica: throughput -------------', NULL) AS section_replica_throughput,

    -- Total
    multiIf(_pretty = 1, concat(toString(round(T0.query_duration_ms/1000.0, 2)), ' s (total)'), toString(round(T0.query_duration_ms/1000.0, 2))) AS replica_total_time,
    multiIf(
        T0.query_duration_ms > 0,
        multiIf(_pretty = 1, concat(formatReadableQuantity(round(T0.ProfileEvents['RowsReadByMainReader'] / (T0.query_duration_ms/1000.0), 2)), ' rows/s'),
                toString(round(T0.ProfileEvents['RowsReadByMainReader'] / (T0.query_duration_ms/1000.0), 2))),
        NULL
    ) AS replica_rows_per_sec_total,
    multiIf(
        T0.query_duration_ms > 0,
        multiIf(_pretty = 1, concat(formatReadableSize(T0.ProfileEvents['CompressedReadBufferBytes'] / (T0.query_duration_ms/1000.0)), '/s'),
                toString(round(T0.ProfileEvents['CompressedReadBufferBytes'] / (T0.query_duration_ms/1000.0), 2))),
        NULL
    ) AS replica_bytes_per_sec_total,

    /* ===== Section: throughput · cold path ===== */
    multiIf(_sections = 1 AND T0.ProfileEvents['DiskConnectionsElapsedMicroseconds'] > 0, '---------------------------- cold path ---', NULL) AS section_replica_cold,

    -- Cold read = local fetch + parallel remote read wait (only if DiskConnectionsElapsedMicroseconds exists)
    if(T0.ProfileEvents['DiskConnectionsElapsedMicroseconds'] > 0,
        multiIf(_pretty = 1,
            concat(
                toString(round( (T0.ProfileEvents['DiskConnectionsElapsedMicroseconds'] + T0.ProfileEvents['ParallelReplicasReadRequestMicroseconds'])/1000000.0 , 2)),
                ' s (cold read)'
            ),
            toString(round( (T0.ProfileEvents['DiskConnectionsElapsedMicroseconds'] + T0.ProfileEvents['ParallelReplicasReadRequestMicroseconds'])/1000000.0 , 2))
        ),
        NULL
    ) AS replica_read_time_cold,

    if(T0.ProfileEvents['DiskConnectionsElapsedMicroseconds'] > 0,
        multiIf(_pretty = 1,
            concat(
                formatReadableQuantity(
                    round(
                        T0.ProfileEvents['RowsReadByMainReader'] /
                        nullIf( (T0.ProfileEvents['DiskConnectionsElapsedMicroseconds'] + T0.ProfileEvents['ParallelReplicasReadRequestMicroseconds'])/1000000.0 , 0)
                    , 2)
                ),
                ' rows/s (cold read)'
            ),
            toString(
                round(
                    T0.ProfileEvents['RowsReadByMainReader'] /
                    nullIf( (T0.ProfileEvents['DiskConnectionsElapsedMicroseconds'] + T0.ProfileEvents['ParallelReplicasReadRequestMicroseconds'])/1000000.0 , 0)
                , 2)
            )
        ),
        NULL
    ) AS replica_rows_per_sec_read_cold,

    if(T0.ProfileEvents['DiskConnectionsElapsedMicroseconds'] > 0,
        multiIf(_pretty = 1,
            concat(
                formatReadableSize(
                    T0.ProfileEvents['CompressedReadBufferBytes'] /
                    nullIf( (T0.ProfileEvents['DiskConnectionsElapsedMicroseconds'] + T0.ProfileEvents['ParallelReplicasReadRequestMicroseconds'])/1000000.0 , 0)
                ),
                '/s (cold read)'
            ),
            toString(
                round(
                    T0.ProfileEvents['CompressedReadBufferBytes'] /
                    nullIf( (T0.ProfileEvents['DiskConnectionsElapsedMicroseconds'] + T0.ProfileEvents['ParallelReplicasReadRequestMicroseconds'])/1000000.0 , 0)
                , 2)
            )
        ),
        NULL
    ) AS replica_bytes_per_sec_read_cold,

    if(T0.ProfileEvents['DiskConnectionsElapsedMicroseconds'] > 0,
        multiIf(_pretty = 1,
            concat(
                toString(
                    round(
                        (T0.query_duration_ms/1000.0) -
                        ((T0.ProfileEvents['DiskConnectionsElapsedMicroseconds'] + T0.ProfileEvents['ParallelReplicasReadRequestMicroseconds'])/1000000.0)
                    , 2)
                ),
                ' s (processing)'
            ),
            toString(
                round(
                    (T0.query_duration_ms/1000.0) -
                    ((T0.ProfileEvents['DiskConnectionsElapsedMicroseconds'] + T0.ProfileEvents['ParallelReplicasReadRequestMicroseconds'])/1000000.0)
                , 2)
            )
        ),
        NULL
    ) AS replica_processing_time_cold,

    /* ===== Section: throughput · hot path ===== */
    multiIf(_sections = 1 AND T0.ProfileEvents['DiskReadElapsedMicroseconds'] > 0, '---------------------------- hot path ---', NULL) AS section_replica_hot,

    -- Hot read = local disk/page cache time
    if(T0.ProfileEvents['DiskReadElapsedMicroseconds'] > 0,
        multiIf(_pretty = 1,
            concat(toString(round(T0.ProfileEvents['DiskReadElapsedMicroseconds']/1000000.0, 2)), ' s (hot read)'),
            toString(round(T0.ProfileEvents['DiskReadElapsedMicroseconds']/1000000.0, 2))
        ),
        NULL
    ) AS replica_read_time_hot,

    if(T0.ProfileEvents['DiskReadElapsedMicroseconds'] > 0,
        multiIf(_pretty = 1,
            concat(
                formatReadableQuantity(
                    round(
                        T0.ProfileEvents['RowsReadByMainReader'] /
                        nullIf(T0.ProfileEvents['DiskReadElapsedMicroseconds']/1000000.0, 0)
                    , 2)
                ),
                ' rows/s (hot read)'
            ),
            toString(
                round(
                    T0.ProfileEvents['RowsReadByMainReader'] /
                    nullIf(T0.ProfileEvents['DiskReadElapsedMicroseconds']/1000000.0, 0)
                , 2)
            )
        ),
        NULL
    ) AS replica_rows_per_sec_read_hot,

    if(T0.ProfileEvents['DiskReadElapsedMicroseconds'] > 0,
        multiIf(_pretty = 1,
            concat(
                formatReadableSize(
                    T0.ProfileEvents['CompressedReadBufferBytes'] /
                    nullIf(T0.ProfileEvents['DiskReadElapsedMicroseconds']/1000000.0, 0)
                ),
                '/s (hot read)'
            ),
            toString(
                round(
                    T0.ProfileEvents['CompressedReadBufferBytes'] /
                    nullIf(T0.ProfileEvents['DiskReadElapsedMicroseconds']/1000000.0, 0)
                , 2)
            )
        ),
        NULL
    ) AS replica_bytes_per_sec_read_hot,

    if(T0.ProfileEvents['DiskReadElapsedMicroseconds'] > 0,
        multiIf(_pretty = 1,
            concat(
                toString(
                    round(
                        (T0.query_duration_ms/1000.0) -
                        (T0.ProfileEvents['DiskReadElapsedMicroseconds']/1000000.0)
                    , 2)
                ),
                ' s (processing)'
            ),
            toString(
                round(
                    (T0.query_duration_ms/1000.0) -
                    (T0.ProfileEvents['DiskReadElapsedMicroseconds']/1000000.0)
                , 2)
            )
        ),
        NULL
    ) AS replica_processing_time_hot,

    /* ===== Section: read stats ===== */
    multiIf(_sections = 1, '-------------- replica: read stats ------------', NULL) AS section_replica_read,
    multiIf(_pretty = 1, concat(formatReadableQuantity(T0.ProfileEvents['ParallelReplicasReadMarks']), ' granules read'), toString(T0.ProfileEvents['ParallelReplicasReadMarks'])) AS replica_granules_read,
    multiIf(_pretty = 1, concat(formatReadableQuantity(T0.ProfileEvents['RowsReadByMainReader']), ' rows read'), toString(T0.ProfileEvents['RowsReadByMainReader'])) AS replica_rows_read,
    multiIf(_pretty = 1, concat(formatReadableQuantity(T0.result_rows), ' rows returned'), toString(T0.result_rows)) AS replica_rows_returned,

    /* ===== Section: bytes & cache ===== */
    multiIf(_sections = 1, '----------- replica: bytes & cache -----------', NULL) AS section_replica_bytes,
    multiIf(_pretty = 1, concat(formatReadableSize(T0.ProfileEvents['CompressedReadBufferBytes']), ' read uncompressed'), toString(T0.ProfileEvents['CompressedReadBufferBytes'])) AS replica_bytes_read,
    multiIf(_pretty = 1, concat(formatReadableSize(T0.ProfileEvents['ThreadpoolReaderReadBytes']), ' read'), toString(T0.ProfileEvents['ThreadpoolReaderReadBytes'])) AS replica_bytes_read_compressed,
    multiIf(_pretty = 1, concat(formatReadableSize(T0.ProfileEvents['CachedReadBufferReadFromCacheBytes']), ' read from local cache'), toString(T0.ProfileEvents['CachedReadBufferReadFromCacheBytes'])) AS replica_bytes_from_cache_compressed,

    /* ===== Section: network ===== */
    multiIf(_sections = 1, '------------- replica: network ---------------', NULL) AS section_replica_network,
    multiIf(_pretty = 1, concat(formatReadableSize(T0.ProfileEvents['NetworkReceiveBytes']), ' received'), toString(T0.ProfileEvents['NetworkReceiveBytes'])) AS replica_net_recv_bytes,
    multiIf(_pretty = 1, concat(formatReadableSize(T0.ProfileEvents['NetworkSendBytes']), ' sent'), toString(T0.ProfileEvents['NetworkSendBytes'])) AS replica_net_sent_bytes

--     , T0.ProfileEvents -- handy for debugging
FROM T0
CROSS JOIN T1
ORDER BY event_time_microseconds DESC
FORMAT JSON
SETTINGS
    skip_unavailable_shards = 1,
    output_format_pretty_single_large_number_tip_threshold = 0;