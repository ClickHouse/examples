#!/bin/bash


log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

set -euo pipefail

# ==============================
# Arguments
# ==============================

if [ $# -ne 4 ]; then
    echo -e "\nUsage: $0 BATCH_SIZE OUTPUT_DIR MAX_ROWS LOG_FILE\n"
    exit 1
fi

BATCH_SIZE="$1"
OUTPUT_DIR="$2"
MAX_ROWS="$3"
LOG_FILE="$4"

# ==============================
# Constants
# ==============================

DATASET_URL="https://datasets.clickhouse.com/hits/tsv/hits.tsv.gz"
CACHE_DIR="./downloads"
RAW_ARCHIVE="$CACHE_DIR/hits.tsv.gz"
RAW_TSV="$CACHE_DIR/hits.tsv"
MARKER_FILE="$OUTPUT_DIR/.complete"

HEADER="WatchID	JavaEnable	Title	GoodEvent	EventTime	EventDate	CounterID	ClientIP	RegionID	UserID	CounterClass	OS	UserAgent	URL	Referer	IsRefresh	RefererCategoryID	RefererRegionID	URLCategoryID	URLRegionID	ResolutionWidth	ResolutionHeight	ResolutionDepth	FlashMajor	FlashMinor	FlashMinor2	NetMajor	NetMinor	UserAgentMajor	UserAgentMinor	CookieEnable	JavascriptEnable	IsMobile	MobilePhone	MobilePhoneModel	Params	IPNetworkID	TraficSourceID	SearchEngineID	SearchPhrase	AdvEngineID	IsArtifical	WindowClientWidth	WindowClientHeight	ClientTimeZone	ClientEventTime	SilverlightVersion1	SilverlightVersion2	SilverlightVersion3	SilverlightVersion4	PageCharset	CodeVersion	IsLink	IsDownload	IsNotBounce	FUniqID	OriginalURL	HID	IsOldCounter	IsEvent	IsParameter	DontCountHits	WithHash	HitColor	LocalEventTime	Age	Sex	Income	Interests	Robotness	RemoteIP	WindowName	OpenerName	HistoryLength	BrowserLanguage	BrowserCountry	SocialNetwork	SocialAction	HTTPError	SendTiming	DNSTiming	ConnectTiming	ResponseStartTiming	ResponseEndTiming	FetchTiming	SocialSourceNetworkID	SocialSourcePage	ParamPrice	ParamOrderID	ParamCurrency 	ParamCurrencyID	OpenstatServiceName	OpenstatCampaignID	OpenstatAdID	OpenstatSourceID 	UTMSource 	UTMMedium	UTMCampaign	UTMContent	UTMTerm	FromTag	HasGCLID 	RefererHash	URLHash 	CLID"
# ==============================
# Download once
# ==============================

if [ ! -f "$RAW_ARCHIVE" ]; then
log "📥 Downloading dataset → $RAW_ARCHIVE"
    mkdir -p "$CACHE_DIR"
    wget --no-verbose --continue -O "$RAW_ARCHIVE" "$DATASET_URL"
else
    log "✅ Dataset already exists"
fi

# ==============================
# Extract once
# ==============================

if [ ! -f "$RAW_TSV" ]; then
    log "📂 Extracting → $RAW_TSV"
    gunzip -c "$RAW_ARCHIVE" > "$RAW_TSV"
else
    log "✅ Already extracted: $RAW_TSV"
fi

# ==============================
# Row Limit Logic (Random Sampling)
# ==============================

log "\n===================================="
log "  Selecting $MAX_ROWS Unique Random Rows"
log "===================================="

TMP_FULL_FILE="$CACHE_DIR/hits.tsv"
RAW_TSV="$CACHE_DIR/hits-${MAX_ROWS}-shuf.tsv"

if [[ ! -f "$RAW_TSV" ]]; then
    log "🔀 Creating randomized subset → $RAW_TSV"
    shuf "$TMP_FULL_FILE" | head -n "$MAX_ROWS" > "$RAW_TSV"
else
    log "✅ Random subset already exists: $RAW_TSV"
fi

# ==============================
# Skip if already done
# ==============================

if [ -f "$MARKER_FILE" ]; then
log "✅ Output already exists: $OUTPUT_DIR (skipping)"
    exit 0
fi

mkdir -p "$OUTPUT_DIR"

# ==============================
# Chunking
# ==============================

log "🔪 Splitting TSV into chunks of $BATCH_SIZE rows..."
# split -l "$BATCH_SIZE" -d --additional-suffix=.tsv "$RAW_TSV" "$OUTPUT_DIR/chunk_"
split -l "$BATCH_SIZE" -d --numeric-suffixes=0 --suffix-length=8 --additional-suffix=.tsv "$RAW_TSV" "$OUTPUT_DIR/chunk_"

# ==============================
# Prepend header to each chunk
# ==============================

log "🪄 Adding header to each chunk..."
for f in "$OUTPUT_DIR"/chunk_*.tsv; do
    tmp="${f}.tmp"
    echo -e "$HEADER" > "$tmp"
    cat "$f" >> "$tmp"
    mv "$tmp" "$f"
done

touch "$MARKER_FILE"


chunk_count=$(ls "$OUTPUT_DIR"/chunk_*.tsv | wc -l)
log "🧩 Total chunks created: $chunk_count"
log "✅ TSV chunking complete."