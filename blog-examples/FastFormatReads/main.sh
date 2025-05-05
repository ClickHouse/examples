#!/bin/bash

LOG_FILE="logs/main_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}


set -euo pipefail


SKIP_GENERATION=0
# SKIP_GENERATION=1


# General information variables
MACHINE="m6i.8xlarge, 10000gib gp3"
SYSTEM="clickhouse-local"
VERSION="25.4.1.2389"
OS="Ubuntu 24.04"
DATE_TODAY=$(date +"%Y-%m-%d")
# TOTAL_NUM_ROWS=10000000
TOTAL_NUM_ROWS=100000000

# ==============================
# Parameters
# ==============================

batch_sizes=(
    "1000000"
)

formats=(
    "Parquet"
    "Arrow"
    "Native"
    "CSV"
    "TabSeparated"
    "JSONEachRow"
    "BSONEachRow"
    "RowBinary"
)

sortings=("true" "false")

compressors=("lz4" "zstd" "none")

# ==============================
# Internal compression mappings
# ==============================

declare -A FORMATS_WITH_BUILT_IN_COMPRESSION_MAP=(
    ["Parquet"]="zstd lz4 snappy brotli gzip none"
    ["Arrow"]="zstd lz4 none"
    ["ArrowStream"]="zstd lz4 none"
    ["Avro"]="zstd snappy deflate none"
)

declare -A FORMATS_WITH_BUILT_IN_COMPRESSION_SETTINGS_MAP=(
    ["Parquet_zstd"]="output_format_parquet_compression_method='zstd'"
    ["Parquet_lz4"]="output_format_parquet_compression_method='lz4'"
    ["Parquet_snappy"]="output_format_parquet_compression_method='snappy'"
    ["Parquet_brotli"]="output_format_parquet_compression_method='brotli'"
    ["Parquet_gzip"]="output_format_parquet_compression_method='gzip'"
    ["Parquet_none"]="output_format_parquet_compression_method='none'"

    ["Arrow_zstd"]="output_format_arrow_compression_method='zstd'"
    ["Arrow_lz4"]="output_format_arrow_compression_method='lz4_frame'"
    ["Arrow_none"]="output_format_arrow_compression_method='none'"

    ["ArrowStream_zstd"]="output_format_arrow_compression_method='zstd'"
    ["ArrowStream_lz4"]="output_format_arrow_compression_method='lz4_frame'"
    ["ArrowStream_none"]="output_format_arrow_compression_method='none'"

    ["Avro_zstd"]="output_format_avro_codec='zstd'"
    ["Avro_snappy"]="output_format_avro_codec='snappy'"
    ["Avro_deflate"]="output_format_avro_codec='deflate'"
    ["Avro_none"]="output_format_avro_codec='null'"
)

declare -A EXTRA_SETTINGS_MAP=(
    ["ProtobufList"]="format_schema='hits.proto:MessageType'"
#     ["Parquet"]="output_format_parquet_row_group_size=100000"
)

# ==============================
# Helpers
# ==============================


get_data_dir() {
    local format="$1"
    local batch_size="$2"
    local sorted="$3"
    local codec="$4"

    local sort_label=$([[ "$sorted" == "true" ]] && echo "sorted" || echo "unsorted")
    local compressor_label=$([[ "$codec" == "none" ]] && echo "uncompressed" || echo "$codec")

    echo "./output/$format/$TOTAL_NUM_ROWS/$batch_size/$sort_label/$compressor_label"
}


generate_raw_tsv() {
    local batch_size="$1"
    local raw_dir="./tsv_raw/$TOTAL_NUM_ROWS/$batch_size"

    if [[ "$SKIP_GENERATION" -eq 1 ]]; then
        log "$raw_dir"
        return
    fi

    if [ ! -f "$raw_dir/.complete" ]; then
log "Generating raw TSV for $batch_size batch size for $TOTAL_NUM_ROWS rows ..."
        ./hits_to_tsv-chunks.sh "$batch_size" "$raw_dir" "$TOTAL_NUM_ROWS" "$LOG_FILE"
    else
log "Reusing existing raw TSV for $batch_size" >&2
    fi

# echo "$raw_dir"
}

convert_format() {

log "\nStarting conversion..."

    local input_dir="$1"
    local format="$2"
    local compressor="$3"
    local batch_size="$4"
    local sorted="$5"

    log "  Format: $format"
    log "  Sorting: $sorted"
    log "  Compressor: $compressor"
    log "  Input Directory: $input_dir"



    local key="${format}_${compressor}"
    local extra_settings=""


    local output_dir=$(get_data_dir "$format" "$batch_size" "$sorted" "$compressor")
    log "  Output Directory: $output_dir"

    if [[ "$SKIP_GENERATION" -eq 1 ]]; then
        return
    fi

    if [[ -n "${FORMATS_WITH_BUILT_IN_COMPRESSION_SETTINGS_MAP[$key]:-}" ]]; then
        extra_settings="${FORMATS_WITH_BUILT_IN_COMPRESSION_SETTINGS_MAP[$key]}"

        # Append any additional format-wide extra settings
        if [[ -n "${EXTRA_SETTINGS_MAP[$format]:-}" ]]; then
            extra_settings="$extra_settings, ${EXTRA_SETTINGS_MAP[$format]}"
        fi


    elif [[ -n "${EXTRA_SETTINGS_MAP[$format]:-}" ]]; then
        extra_settings="${EXTRA_SETTINGS_MAP[$format]}"
    fi

    mkdir -p "$output_dir"



log "  Extra Settings: $extra_settings"

    ./convert_tsv-chunks.sh "$format" "$sorted" "$input_dir" "$output_dir" "$LOG_FILE" "$extra_settings"
}

compress_format_externally() {
    local input_dir="$1"
    local format="$2"
    local compressor="$3"
    local batch_size="$4"
    local sorted="$5"


    local output_dir=$(get_data_dir "$format" "$batch_size" "$sorted" "$compressor")

    if [[ "$SKIP_GENERATION" -eq 1 ]]; then
        return
    fi

    mkdir -p "$output_dir"

log "Compressing $format files with $compressor → $output_dir"
    for file in "$input_dir"/*; do
        [ -f "$file" ] || continue
        local filename=$(basename "$file")
        case "$compressor" in
            gzip) gzip -c "$file" > "$output_dir/$filename.gz" ;;
            lz4)  lz4 -c "$file" > "$output_dir/$filename.lz4" ;;
            zstd) zstd -c "$file" > "$output_dir/$filename.zstd" ;;
        esac
    done
}

run_benchmark() {
    local batch_size="$1"
    local sorted="$2"
    local codec="$3"
    local format="$4"
    local data_dir="$5"
    local dirname="$6"

    # derive sort_label from the sorted flag
    local sort_label=$([[ "$sorted" == "true" ]] && echo "sorted" || echo "unsorted")
    # map codec none to label 'uncompressed'
    local codec_label=$([[ "$codec" == "none" ]] && echo "uncompressed" || echo "$codec")

    # ensure output dir exists
    mkdir -p "$dirname"

    local runtimes_file="$dirname/runtimes_${format}_${batch_size}_${sort_label}_${codec_label}.json"
    local memory_file="$dirname/memory_${format}_${batch_size}_${sort_label}_${codec_label}.json"

    # Create log comment string with current timestamp
    local timestamp=$(date +%s)
    local log_comment="${batch_size}_${sort_label}_${codec_label}_${format}_${timestamp}"

    log "  → Benchmarking (${codec_label}): ${data_dir}"
    ./benchmark.sh "$data_dir" "$format" "$log_comment" "$runtimes_file" "$memory_file" "$LOG_FILE" "queries.sql"

    sleep 10

    # Run metrics.sql with substituted log_comment
    METRICS_SQL_TMP="metrics_tmp.sql"
    sed "s/{LOG_COMMENT}/$log_comment/g" metrics.sql > "$METRICS_SQL_TMP"

    METRICS_FILE="$dirname/metrics_${format}_${batch_size}_${sort_label}_${codec_label}.txt"
    clickhouse-client --query="$(cat "$METRICS_SQL_TMP")" > "$METRICS_FILE"

    log "✓ Metrics written to $METRICS_FILE"

    # Parse grouped metrics from metrics file
    read_rows=$(grep "read_rows:" "$METRICS_FILE" | sed 's/^.*read_rows:[[:space:]]*//')
    read_bytes=$(grep "read_bytes:" "$METRICS_FILE" | sed 's/^.*read_bytes:[[:space:]]*//')
    threads_participating=$(grep "threads_participating:" "$METRICS_FILE" | sed 's/^.*threads_participating:[[:space:]]*//')
    threads_simultaneous_peak=$(grep "threads_simultaneous_peak:" "$METRICS_FILE" | sed 's/^.*threads_simultaneous_peak:[[:space:]]*//')
    concurrency_control_slots_acquired=$(grep "concurrency_control_slots_acquired:" "$METRICS_FILE" | sed 's/^.*concurrency_control_slots_acquired:[[:space:]]*//')
    disk_read_elapsed=$(grep "disk_read_elapsed:" "$METRICS_FILE" | sed 's/^.*disk_read_elapsed:[[:space:]]*//')


    # Calculate total size of all files in data_dir
    local total_size_bytes
    total_size_bytes=$(find "$data_dir" -type f -exec stat --format="%s" {} + | awk '{total += $1} END {print total}')

    local first_file_size
    first_file_size=$(find "$data_dir" -type f | sort | head -n 1 | xargs stat --format="%s")

    local file_count
    file_count=$(find "$data_dir" -type f | wc -l)

    local num_rows_per_file=$(( $TOTAL_NUM_ROWS / $file_count ))

    # Prepare JSON output
    local timestamp=$(date +%s)
    local results_file="results/${format,,}_${TOTAL_NUM_ROWS}_${batch_size}_${sort_label}_${codec_label}_${timestamp}.json"
    mkdir -p results

    # Detect compression type
    local compression_type
    if [[ -n "${FORMATS_WITH_BUILT_IN_COMPRESSION_MAP[$format]:-}" ]]; then
        compression_type="built-in compression"
    elif [[ "$codec" != "none" ]]; then
        compression_type="external compression"
    else
        compression_type="uncompressed"
    fi

    extra_settings=""
    if [[ -n "${EXTRA_SETTINGS_MAP[$format]:-}" ]]; then
        extra_settings="${EXTRA_SETTINGS_MAP[$format]}"
    fi

    # Read runtimes and memory arrays as JSON-compatible lists
    local runtimes_json memory_json
    runtimes_json=$(awk 'BEGIN { ORS=""; print "[" } { gsub(/^[ \t]+|[ \t]+$/, ""); print $0; if (NR != 0) print "," } END { print "]" }' "$runtimes_file" | sed 's/,\]$/]/')
    memory_json=$(awk 'BEGIN { ORS=""; print "[" } { gsub(/^[ \t]+|[ \t]+$/, ""); print $0; if (NR != 0) print "," } END { print "]" }' "$memory_file" | sed 's/,\]$/]/')

    # Write JSON results
    echo -e "{\n  \"system\": \"$SYSTEM\",\n  \"version\": \"$VERSION\",\n  \"os\": \"$OS\",\n  \"date\": \"$DATE_TODAY\",\n  \"machine\": \"$MACHINE\",\n  \"total_num_rows\": $TOTAL_NUM_ROWS,\n  \"data_size\": $total_size_bytes,\n  \"files\": $file_count,\n  \"file_size\": $first_file_size,\n  \"num_rows_per_file\": $num_rows_per_file,\n  \"format\": \"$format\",\n  \"batch_size\": $batch_size,\n  \"extra_settings\": \"$extra_settings\",\n  \"sorted\": $sorted,\n  \"compressor\": \"$codec\",\n  \"compression_type\": \"$compression_type\",\n  \"runtime_result\": $runtimes_json,\n  \"memory_result\": $memory_json,\n  \"read_rows\": $read_rows,\n  \"read_bytes\": $read_bytes,\n  \"threads_participating\": $threads_participating,\n  \"threads_simultaneous_peak\": $threads_simultaneous_peak,\n  \"concurrency_control_slots_acquired\": $concurrency_control_slots_acquired,\n  \"disk_read_elapsed\": $disk_read_elapsed\n}" > "$results_file"

    log "JSON benchmark results saved to $results_file"

}




# ==============================
# Main Loop
# ==============================

for batch_size in "${batch_sizes[@]}"; do

    generate_raw_tsv "$batch_size"

    raw_tsv_dir="./tsv_raw/$TOTAL_NUM_ROWS/$batch_size"

    for format in "${formats[@]}"; do

        for sorted in "${sortings[@]}"; do
            log "\n=== Processing: batch_size=$batch_size, sorted=$sorted ==="

            if [[ -n "${FORMATS_WITH_BUILT_IN_COMPRESSION_MAP[$format]:-}" ]]; then
                for codec in ${FORMATS_WITH_BUILT_IN_COMPRESSION_MAP[$format]}; do
                    if [[ " ${compressors[*]} " =~ " $codec " ]]; then
                        convert_format "$raw_tsv_dir" "$format" "$codec" "$batch_size" "$sorted"

                        data_dir=$(get_data_dir "$format" "$batch_size" "$sorted" "$codec")

                        run_benchmark "$batch_size" "$sorted" "$codec" "$format" "$data_dir" "./result_snippets"
                    else
                        log "Skipping $format with unsupported built-in codec: $codec"
                    fi
                done
            else
                convert_format "$raw_tsv_dir" "$format" "none" "$batch_size" "$sorted"

                data_dir_uncompressed=$(get_data_dir "$format" "$batch_size" "$sorted" "none")
                data_dir=''

                for codec in "${compressors[@]}"; do
                    if [[ "$codec" != "none" ]]; then
                        compress_format_externally "$data_dir_uncompressed" "$format" "$codec" "$batch_size" "$sorted"

                        data_dir=$(get_data_dir "$format" "$batch_size" "$sorted" "$codec")

                    else
                        data_dir="$data_dir_uncompressed"
                    fi

                    run_benchmark "$batch_size" "$sorted" "$codec" "$format" "$data_dir" "./result_snippets"
                done
            fi

        done
    done
done

echo -e "\n✅ Done: all data generated in ./output/*"
