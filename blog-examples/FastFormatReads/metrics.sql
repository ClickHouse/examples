WITH
    3 AS groupSize,
    base AS
    (
        SELECT
            groupArray(read_rows) AS read_rows,
            groupArray(read_bytes) AS read_bytes,
            groupArray(threads_participating) AS threads_participating,
            groupArray(threads_simultaneous_peak) AS threads_simultaneous_peak,
            groupArray(ProfileEvents_ConcurrencyControlSlotsAcquired) AS concurrency_control_slots_acquired,
            groupArray(ProfileEvents_DiskReadElapsedMicroseconds) AS read_elapsed
        FROM
        (
            SELECT
                read_rows,
                read_bytes,
                length(thread_ids) AS threads_participating,
                peak_threads_usage AS threads_simultaneous_peak,
                ProfileEvents['ConcurrencyControlSlotsAcquired'] AS ProfileEvents_ConcurrencyControlSlotsAcquired,
                ProfileEvents['DiskReadElapsedMicroseconds'] AS ProfileEvents_DiskReadElapsedMicroseconds
            FROM system.query_log
            WHERE (query_kind = 'Select') AND (type = 'QueryFinish') AND is_initial_query AND (log_comment = '{LOG_COMMENT}')
            ORDER BY event_time ASC
        )
    )
SELECT
    arrayMap(i -> arraySlice(read_rows, ((i - 1) * groupSize) + 1, groupSize), range(1, intDiv((length(read_rows) + groupSize) - 1, groupSize) + 1)) AS read_rows,
    arrayMap(i -> arraySlice(read_bytes, ((i - 1) * groupSize) + 1, groupSize), range(1, intDiv((length(read_bytes) + groupSize) - 1, groupSize) + 1)) AS read_bytes,
    arrayMap(i -> arraySlice(threads_participating, ((i - 1) * groupSize) + 1, groupSize), range(1, intDiv((length(threads_participating) + groupSize) - 1, groupSize) + 1)) AS threads_participating,
    arrayMap(i -> arraySlice(threads_simultaneous_peak, ((i - 1) * groupSize) + 1, groupSize), range(1, intDiv((length(threads_simultaneous_peak) + groupSize) - 1, groupSize) + 1)) AS threads_simultaneous_peak,
    arrayMap(i -> arraySlice(concurrency_control_slots_acquired, ((i - 1) * groupSize) + 1, groupSize), range(1, intDiv((length(concurrency_control_slots_acquired) + groupSize) - 1, groupSize) + 1)) AS concurrency_control_slots_acquired,
    arrayMap(i -> arraySlice(read_elapsed, ((i - 1) * groupSize) + 1, groupSize), range(1, intDiv((length(read_elapsed) + groupSize) - 1, groupSize) + 1)) AS disk_read_elapsed
FROM base
FORMAT Vertical