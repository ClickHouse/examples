#!/bin/bash
set -euxo pipefail

# Check for required parameters
if [ "$#" -ne 4 ]; then
    echo "Usage: $0 <start_time> <end_time> <expected_query_count> <tries>"
    echo "Times should be in format: YYYY-MM-DD HH:MM:SS"
    exit 1
fi

START_TIME="$1"
END_TIME="$2"
EXPECTED_COUNT="$3"
TRIES="$4"
CURRENT_DATE=$(echo "$START_TIME" | cut -d' ' -f1)
OUTPUT_FILE="results/serverless_100b.json"

mkdir -p results

TEMP_FILE=$(mktemp)
psql -h "${FQDN:-localhost}" -U dev -d dev -p 5439 -t -A -F '|' -c "
WITH
daily_cost AS (
    SELECT
        trunc(start_time) AS select_day,
        MAX(compute_capacity) AS max_compute_capacity,
        (SUM(compute_seconds) / 3600::double precision) AS total_compute_hour,
        (SUM(charged_seconds) / 3600::double precision) AS total_charged_hour
    FROM sys_serverless_usage
    GROUP BY 1
),
daily_queries AS (
    SELECT
        *,
        elapsed_time / total_time_for_day::double precision AS perc
    FROM (
        SELECT
            query_id,
            user_query_hash,
            user_id,
            query_text,
            trunc(start_time) AS select_day,
            start_time,
            elapsed_time,
            queue_time,
            execution_time,
            compile_time,
            SUM(elapsed_time) OVER (PARTITION BY trunc(start_time)) AS total_time_for_day
        FROM sys_query_history
    ) t
)
SELECT
    q.query_id::varchar || '|' ||
    q.elapsed_time::varchar || '|' ||
    q.queue_time::varchar || '|' ||
    q.execution_time::varchar || '|' ||
    q.compile_time::varchar || '|' ||
    q.start_time::varchar || '|' ||
    q.perc::varchar || '|' ||
    c.max_compute_capacity::varchar || '|' ||
    c.total_compute_hour::varchar || '|' ||
    c.total_charged_hour::varchar
FROM daily_cost c
JOIN daily_queries q USING (select_day)
WHERE q.select_day = DATE '$CURRENT_DATE'
  AND q.start_time >= '$START_TIME'::timestamp 
  AND q.start_time <  '$END_TIME'::timestamp
  AND q.user_id = 102
  AND q.user_query_hash != 'VBjvFuZqb3Q='
ORDER BY q.start_time ASC;
" -o "$TEMP_FILE"

# Initialize arrays for query times with size equals to expected query count
query_times=()

# Process the file to group times by query_id
while IFS='|' read -r line; do
    
    elapsed_time=$(echo "$line" | awk -F'|' '{print $2}' | tr -d ' ')
    # Convert from microseconds to seconds with 3 decimal places and ensure leading zero
    elapsed_seconds=$(echo "scale=3; $elapsed_time / 1000000" | bc | awk '{printf "%.3f", $0}')
    query_times+=("$elapsed_seconds")

done < "$TEMP_FILE"

# group into arrays of 3 (adjust chunk size as you need)
chunk_size=3
result="["
for ((i=0; i<${#query_times[@]}; i+=chunk_size)); do
    if [ $i -gt 0 ]; then
        result+=", "
    fi
    result+="["
    for ((j=0; j<chunk_size && (i+j)<${#query_times[@]}; j++)); do
        if [ $j -gt 0 ]; then
            result+=", "
        fi
        result+="${query_times[i+j]}"
    done
    result+="]"
done
result+="]"

# Initialize arrays for query times with size equals to expected query count
billed_times=()

# Process the file to group times by query_id
while IFS='|' read -r line; do
    
    total_compute_hour=$(echo "$line" | awk -F'|' '{print $9}' | tr -d ' ')
    perc=$(echo "$line" | awk -F'|' '{print $7}' | tr -d ' ')
    # Calculate billed time in seconds (convert hours to seconds: * 3600)
    billed_time=$(echo "scale=3; $total_compute_hour * $perc * 3600" | bc | awk '{printf "%.3f", $0}')
    billed_times+=("$billed_time")

done < "$TEMP_FILE"

# group into arrays of 3 (adjust chunk size as you need)
chunk_size=3
billed_result="["
for ((i=0; i<${#billed_times[@]}; i+=chunk_size)); do
    if [ $i -gt 0 ]; then
        billed_result+=", "
    fi
    billed_result+="["
    for ((j=0; j<chunk_size && (i+j)<${#billed_times[@]}; j++)); do
        if [ $j -gt 0 ]; then
            billed_result+=", "
        fi
        billed_result+="${billed_times[i+j]}"
    done
    billed_result+="]"
done
billed_result+="]"

# Generate the JSON output
cat > "$OUTPUT_FILE" << EOF
{
    "system": "Redshift Serverless",
    "date": "$CURRENT_DATE",
    "machine": "serverless",
    "cluster_size": "serverless",
    "proprietary": "yes",
    "tuned": "no",
    "comment": "",
    "tags": ["serverless", "column-oriented", "aws", "managed"],
    "load_time": 1889,
    "data_size": 30300000000,
    "result": $result,
    "billed_times": $billed_result
}
EOF

rm -f "$TEMP_FILE"
echo "Results saved to $OUTPUT_FILE"
