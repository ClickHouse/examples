#!/bin/bash
set -euo pipefail


log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}


# =========================================
# Usage / Arguments
# =========================================
if [[ $# -lt 4 ]]; then
    echo "Usage: $0 DATA_DIRECTORY FORMAT LOG_COMMENT LOG_FILE [QUERIES_FILE]"
    echo "Example: $0 /home/ubuntu/FastFormatReads/output/TabSeparated/1000000/unsorted/zstd TabSeparated queries.sql"
    exit 1
fi

DATA_DIR="$1"                         # e.g. /home/.../unsorted/zstd
FORMAT="$2"                           # e.g. TabSeparated
LOG_COMMENT="$3"
LOG_FILE="$4"
QUERIES_FILE="${5:-queries.sql}"      # defaults to queries.sql if not passed
TRIES=3

# Fixed column schema:
TABLE_STRUCTURE="WatchID Int64, JavaEnable Int16, Title String, GoodEvent Int16, EventTime DateTime, EventDate Date, CounterID Int32, ClientIP Int32, RegionID Int32, UserID Int64, CounterClass Int16, OS Int16, UserAgent Int16, URL String, Referer String, IsRefresh Int16, RefererCategoryID Int16, RefererRegionID Int32, URLCategoryID Int16, URLRegionID Int32, ResolutionWidth Int16, ResolutionHeight Int16, ResolutionDepth Int16, FlashMajor Int16, FlashMinor Int16, FlashMinor2 String, NetMajor Int16, NetMinor Int16, UserAgentMajor Int16, UserAgentMinor String, CookieEnable Int16, JavascriptEnable Int16, IsMobile Int16, MobilePhone Int16, MobilePhoneModel String, Params String, IPNetworkID Int32, TraficSourceID Int16, SearchEngineID Int16, SearchPhrase String, AdvEngineID Int16, IsArtifical Int16, WindowClientWidth Int16, WindowClientHeight Int16, ClientTimeZone Int16, ClientEventTime DateTime, SilverlightVersion1 Int16, SilverlightVersion2 Int16, SilverlightVersion3 Int32, SilverlightVersion4 Int16, PageCharset String, CodeVersion Int32, IsLink Int16, IsDownload Int16, IsNotBounce Int16, FUniqID Int64, OriginalURL String, HID Int32, IsOldCounter Int16, IsEvent Int16, IsParameter Int16, DontCountHits Int16, WithHash Int16, HitColor String, LocalEventTime DateTime, Age Int16, Sex Int16, Income Int16, Interests Int16, Robotness Int16, RemoteIP Int32, WindowName Int32, OpenerName Int32, HistoryLength Int16, BrowserLanguage String, BrowserCountry String, SocialNetwork String, SocialAction String, HTTPError Int16, SendTiming Int32, DNSTiming Int32, ConnectTiming Int32, ResponseStartTiming Int32, ResponseEndTiming Int32, FetchTiming Int32, SocialSourceNetworkID Int16, SocialSourcePage String, ParamPrice Int64, ParamOrderID String, ParamCurrency String, ParamCurrencyID Int16, OpenstatServiceName String, OpenstatCampaignID String, OpenstatAdID String, OpenstatSourceID String, UTMSource String, UTMMedium String, UTMCampaign String, UTMContent String, UTMTerm String, FromTag String, HasGCLID Int16, RefererHash Int64, URLHash Int64, CLID Int32"


# =========================================
# Process each query
# =========================================
while IFS= read -r query || [[ -n "$query" ]]; do
    # skip blanks/comments
    [[ -z "$query" || "${query:0:1}" == "--" ]] && continue

    # clear OS cache
    log "Clearing file system cache..."
    sync
    echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null
    log "File system cache cleared."

    log "Running query: $query"

    # build the file(...) expression
    FILE_EXPR="file('${DATA_DIR}/chunk_*','${FORMAT}','${TABLE_STRUCTURE}')"
    adapted_query="${query/FROM hits/FROM $FILE_EXPR}"

#     echo "About to run:"
#     echo "$adapted_query"

    # execute TRIES times, feeding SQL via stdin
    for run in $(seq 1 $TRIES); do
        clickhouse-client \
          --time \
          --memory-usage \
          --progress 0 \
          --log_comment="${LOG_COMMENT}" \
          --format=Null <<EOF
$adapted_query;
EOF
    done

done < "$QUERIES_FILE"