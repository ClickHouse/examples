#!/bin/bash


log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}


# Ensure at least five parameters (OUTPUT_FORMAT, SORT, INPUT_DIR, OUTPUT_DIR, EXTRA_SETTINGS) are provided
if [ $# -lt 5 ]; then
    echo -e "\nUsage: $0 OUTPUT_FORMAT SORT INPUT_DIR OUTPUT_DIR LOG_FILE [EXTRA_SETTINGS] [TEST_MODE]\n"
    exit 1
fi

# Assign parameters
OUTPUT_FORMAT="$1"
OUTPUT_FORMAT_LOWER=$(echo "$OUTPUT_FORMAT" | tr '[:upper:]' '[:lower:]')
SORT="$2"
INPUT_DIR="$3"
OUTPUT_DIR="$4"
LOG_FILE="$5"
EXTRA_SETTINGS="${6:-}"
TEST_MODE="${7:-false}"

# Remove OUTPUT_DIR if it already exists, then recreate it
if [ -d "$OUTPUT_DIR" ]; then
log "Removing existing directory: $OUTPUT_DIR"
    rm -rf "$OUTPUT_DIR"
fi

mkdir -p "$OUTPUT_DIR"



log "\n===================================="
log "  Converting TSV to $OUTPUT_FORMAT"
log "  Input Directory: $INPUT_DIR"
log "  Output Directory: $OUTPUT_DIR"
log "  Sorting Enabled: $SORT"
log "  Extra Settings: $EXTRA_SETTINGS"
log "  Test Mode: $TEST_MODE"
log "===================================="

TABLE_STRUCTURE="WatchID Int64, JavaEnable Int16, Title String, GoodEvent Int16, EventTime DateTime, EventDate Date, CounterID Int32, ClientIP Int32, RegionID Int32, UserID Int64, CounterClass Int16, OS Int16, UserAgent Int16, URL String, Referer String, IsRefresh Int16, RefererCategoryID Int16, RefererRegionID Int32, URLCategoryID Int16, URLRegionID Int32, ResolutionWidth Int16, ResolutionHeight Int16, ResolutionDepth Int16, FlashMajor Int16, FlashMinor Int16, FlashMinor2 String, NetMajor Int16, NetMinor Int16, UserAgentMajor Int16, UserAgentMinor String, CookieEnable Int16, JavascriptEnable Int16, IsMobile Int16, MobilePhone Int16, MobilePhoneModel String, Params String, IPNetworkID Int32, TraficSourceID Int16, SearchEngineID Int16, SearchPhrase String, AdvEngineID Int16, IsArtifical Int16, WindowClientWidth Int16, WindowClientHeight Int16, ClientTimeZone Int16, ClientEventTime DateTime, SilverlightVersion1 Int16, SilverlightVersion2 Int16, SilverlightVersion3 Int32, SilverlightVersion4 Int16, PageCharset String, CodeVersion Int32, IsLink Int16, IsDownload Int16, IsNotBounce Int16, FUniqID Int64, OriginalURL String, HID Int32, IsOldCounter Int16, IsEvent Int16, IsParameter Int16, DontCountHits Int16, WithHash Int16, HitColor String, LocalEventTime DateTime, Age Int16, Sex Int16, Income Int16, Interests Int16, Robotness Int16, RemoteIP Int32, WindowName Int32, OpenerName Int32, HistoryLength Int16, BrowserLanguage String, BrowserCountry String, SocialNetwork String, SocialAction String, HTTPError Int16, SendTiming Int32, DNSTiming Int32, ConnectTiming Int32, ResponseStartTiming Int32, ResponseEndTiming Int32, FetchTiming Int32, SocialSourceNetworkID Int16, SocialSourcePage String, ParamPrice Int64, ParamOrderID String, ParamCurrency String, ParamCurrencyID Int16, OpenstatServiceName String, OpenstatCampaignID String, OpenstatAdID String, OpenstatSourceID String, UTMSource String, UTMMedium String, UTMCampaign String, UTMContent String, UTMTerm String, FromTag String, HasGCLID Int16, RefererHash Int64, URLHash Int64, CLID Int32"

# Get sorted list of files
mapfile -t TSV_FILES < <(find "$INPUT_DIR" -maxdepth 1 -name 'chunk_*.tsv' | sort)

# If TEST_MODE is enabled, process only the first two files
if [ "$TEST_MODE" == "true" ]; then
    TSV_FILES=("${TSV_FILES[@]:0:2}")  # Slice array to first 2 elements
fi

# Define base settings clause
BASE_SETTINGS="input_format_allow_errors_num = 1_000_000_000, input_format_allow_errors_ratio=1"

# Process each TSV file
for tsv_file in "${TSV_FILES[@]}"; do
    # Extract filename without extension
    base_name=$(basename "$tsv_file" .tsv)

    # Define output file path with dynamic format extension
    output_file="$OUTPUT_DIR/${base_name}.${OUTPUT_FORMAT_LOWER}"

    log "Processing: $tsv_file → $output_file"

    # Define sort clause
    SORT_CLAUSE=""
    if [ "$SORT" == "true" ]; then
        SORT_CLAUSE="ORDER BY CounterID, EventDate, UserID, EventTime, WatchID"
    fi

    # Append extra settings if provided
    if [ -n "$EXTRA_SETTINGS" ]; then
        SETTINGS_CLAUSE="SETTINGS $BASE_SETTINGS, $EXTRA_SETTINGS"
    else
        SETTINGS_CLAUSE="SETTINGS $BASE_SETTINGS"
    fi

    # Construct the query with extracted clauses
    QUERY="INSERT INTO TABLE FUNCTION file('$output_file', '$OUTPUT_FORMAT', '$TABLE_STRUCTURE') SELECT * FROM file('$tsv_file', 'TabSeparatedWithNames', '$TABLE_STRUCTURE') $SORT_CLAUSE $SETTINGS_CLAUSE"

#     echo "$QUERY"

    # Convert TSV to specified format using clickhouse-local
    clickhouse-local --query="$QUERY"

    # Check if conversion was successful
    if [ $? -eq 0 ]; then
        log "Successfully converted: $output_file"
    else
        log "Error converting: $tsv_file"
    fi
done

log "\nAll conversions completed successfully!"