#!/usr/bin/env bash
set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "❌ jq is required"; exit 1; }
command -v clickhouse >/dev/null 2>&1 || { echo "❌ clickhouse client not found"; exit 1; }

# ---------------------------------------
# ClickHouse environment / client wrapper
# ---------------------------------------
# Defaults allow localhost dev with no password & no TLS.
CH_HOST="${CH_HOST:-localhost}"
CH_USER="${CH_USER:-default}"
CH_PASSWORD="${CH_PASSWORD-}"          # may be empty / unset
CH_SECURE="${CH_SECURE:-}"             # set to true/1/yes to enable --secure

# Build client command with optional flags
CH_SECURE_FLAG=""
if [[ "${CH_SECURE,,}" =~ ^(1|true|yes)$ ]]; then
  CH_SECURE_FLAG="--secure"
fi

CH_PASSWORD_PART=""
if [[ -n "${CH_PASSWORD}" ]]; then
  CH_PASSWORD_PART="--password ${CH_PASSWORD}"
fi

CH_CLIENT="clickhouse client --host ${CH_HOST} --user ${CH_USER} ${CH_PASSWORD_PART} ${CH_SECURE_FLAG}"


# ---------------------------------------
# Args (10 required + 1 optional)
# ---------------------------------------
if [[ $# -lt 10 || $# -gt 11 ]]; then
  echo "Usage: $0 <results_dir> <query_db> <query_file> <runs_per_combination> <node_list> <cores_list> <ram_gb_per_node> <csp> <region> <drop_caches> [env]"
  echo "  env (optional): 'cloud' (default) or 'oss'"
  exit 1
fi

RESULTS_DIR="$1"
QUERY_DB="$2"
QUERY_FILE="$3"
RUNS_PER_COMBINATION="$4"
NODE_LIST="$5"
CORES_LIST="$6"
RAM_GB_PER_NODE="$7"
CSP="$8"
REGION="$9"

case "${10,,}" in
  true|1|yes|y)  DROP_CACHES="true" ;;
  false|0|no|n)  DROP_CACHES="false" ;;
  *) echo "DROP_CACHES must be true/false"; exit 1 ;;
esac

ENV="${11:-cloud}"                        # cloud | oss
ENV="${ENV,,}"
if [[ ! "$ENV" =~ ^(cloud|oss)$ ]]; then
  echo "env must be 'cloud' or 'oss' (got: $ENV)"; exit 1
fi

# ---------------------------------------
# Inputs / files
# ---------------------------------------
STATS_SQL_FILE="${STATS_SQL_FILE:-aggregation_stats.sql}"   # placeholders: {lc:String}, {pretty:String}, {sections:String}

# Read query (strip trailing semicolon)
QUERY_SQL="$(sed 's/[[:space:]]*;[[:space:]]*$//' "$QUERY_FILE")"

mkdir -p "$RESULTS_DIR" "$RESULTS_DIR/stats"

DATE="$(date +%F)"
TIME="$(date +%H%M%S)"
STATS_GROUP="${DATE}_${TIME}"            # session folder under stats/
NODE_TAG="$(echo "$NODE_LIST" | tr ' ' '_')"
CORES_TAG="$(echo "$CORES_LIST" | tr ' ' '_')"
SUMMARY_FILE="$RESULTS_DIR/summary_matrix-nodes-${NODE_TAG}_cores-${CORES_TAG}_${DATE}_${TIME}.json"

# Detect ClickHouse version (override with CH_VERSION env if set)
CH_VERSION="${CH_VERSION:-$($CH_CLIENT --query "SELECT version()" | tr -d '[:space:]')}"

# ---------------------------------------
# Helpers
# ---------------------------------------
drop_caches_cloud() {
  echo "🧹 Dropping ClickHouse caches on cluster (Cloud mode)..."
  $CH_CLIENT --distributed_ddl_task_timeout=-1 --query "SYSTEM DROP FILESYSTEM CACHE ON CLUSTER default"
  $CH_CLIENT --distributed_ddl_task_timeout=-1 --query "SYSTEM DROP MARK CACHE ON CLUSTER default"
  $CH_CLIENT --distributed_ddl_task_timeout=-1 --query "SYSTEM DROP QUERY CONDITION CACHE ON CLUSTER default"
  echo "... done"
}

drop_caches_oss() {
  echo "🧹 Dropping OS page cache on this host (OSS mode)..."
  sync
  if [[ -w /proc/sys/vm/drop_caches ]]; then
    echo 3 > /proc/sys/vm/drop_caches
  elif command -v sudo >/dev/null 2>&1; then
    if sudo -n true 2>/dev/null; then
      echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null
    else
      echo "⚠️  Skipping OS cache drop: sudo requires a TTY/password." >&2
      return 1
    fi
  else
    echo "⚠️  Skipping OS cache drop: /proc/sys/vm/drop_caches not writable and sudo not found." >&2
    return 1
  fi
  echo "... file system cache cleared."
}

drop_caches() {
  case "$ENV" in
    cloud) drop_caches_cloud ;;
    oss)   drop_caches_oss   ;;
  esac
}

# Build the stats SQL for given placeholders
build_stats_sql() {
  local LC="$1" PRETTY="$2" SECTIONS="$3"
  local lc_sql_quoted="'${LC//\'/\'\'}'"
  sed \
    -e "s/{lc:String}/$lc_sql_quoted/g" \
    -e "s/{pretty:String}/$PRETTY/g" \
    -e "s/{sections:String}/$SECTIONS/g" \
    "$STATS_SQL_FILE"
}

# Write one JSON file from the built SQL (only .data for compactness)
write_stats_json() {
  local sql="$1" outfile="$2"
  $CH_CLIENT --query "$sql" | jq '.data' > "$outfile"
}

# Flush once, then emit both pretty and raw variants
dump_run_stats_pair() {
  local LC="$1" OUTBASE="$2"   # OUTBASE like: <results>/stats/<session>/<combo>/run_3

  if [[ "$ENV" == "cloud" ]]; then
    echo "Flushing system logs (cloud mode)..."
    $CH_CLIENT --distributed_ddl_task_timeout=-1 --query "SYSTEM FLUSH LOGS ON CLUSTER default"
    echo "... done"
  else
    echo "Sleeping 10s to allow logs to flush (oss mode)..."
    sleep 10
    echo "... done"
  fi

  local sql_pretty sql_raw
  sql_pretty="$(build_stats_sql "$LC" "1" "1")"
  sql_raw="$(build_stats_sql "$LC" "0" "0")"

  write_stats_json "$sql_pretty" "${OUTBASE}_pretty.json"
  write_stats_json "$sql_raw"    "${OUTBASE}_raw.json"
}


run_with_time() {
  local query="$1" nodes="$2" cores="$3" enable_filesystem_cache="$4" log_comment="$5"
  local out rc elapsed

  out=$($CH_CLIENT --database "$QUERY_DB" \
        --log_comment="${log_comment}" \
        --time --progress 0 \
        --use_query_condition_cache=0 \
        --enable_filesystem_cache="${enable_filesystem_cache}" \
        --enable_parallel_replicas=1 \
        --max_parallel_replicas="$nodes" \
        --max_threads="$cores" \
        --query="$query" 2>&1)
  rc=$?

  elapsed=$(printf '%s\n' "$out" | sed -n 's/.*Elapsed: \([0-9]\+\(\.[0-9]\+\)\?\) sec.*/\1/p' | tail -n1)
  if [[ -z "$elapsed" ]]; then
    elapsed=$(printf '%s\n' "$out" | grep -E '^[[:space:]]*[0-9]+(\.[0-9]+)?[[:space:]]*$' | awk '{print $1}' | tail -n1)
  fi
  if [[ $rc -ne 0 || -z "$elapsed" ]]; then
    echo "❌ clickhouse-client failed or no timing found for query"
    echo "---- client output (tail) ----" >&2
    printf '%s\n' "$out" | tail -n 20 >&2
    echo "------------------------------" >&2
    return 1
  fi
  echo "$elapsed"
}

# -------- Aggregators (jq) --------

# EXCLUDING initiator:
# Return 5 values (TSV):
#   avg_mem_bytes  avg_read_bytes  avg_net_sent_bytes  sum_net_sent_bytes  avg_pct
raw_aggregates_excl_initiator() {
  local raw_file="$1"
  jq -r '
    map(select(.is_initiator_node!=1)) as $nodes |
    ($nodes | map(.replica_memory_usage        | select(.!=null) | tonumber)) as $m |
    ($nodes | map(.replica_bytes_read          | select(.!=null) | tonumber)) as $r |
    ($nodes | map(.replica_net_sent_bytes      | select(.!=null) | tonumber)) as $s |
    ($nodes | map(.replica_percentage_processed| select(.!=null) | tonumber)) as $p |
    ($m|length) as $ml | ($r|length) as $rl | ($s|length) as $sl | ($p|length) as $pl |
    [
      (if $ml>0 then ($m|add)/$ml else 0 end),
      (if $rl>0 then ($r|add)/$rl else 0 end),
      (if $sl>0 then ($s|add)/$sl else 0 end),
      (if $sl>0 then  $s|add      else 0 end),
      (if $pl>0 then ($p|add)/$pl else 0 end)
    ] | @tsv
  ' "$raw_file"
}

# INCLUDING initiator:
# Return two averages (TSV): avg_pct  avg_bytes_read
avg_pct_and_bytesread_incl_initiator() {
  local raw_file="$1"
  jq -r '
    [.[].replica_percentage_processed | select(.!=null) | tonumber] as $p |
    [.[].replica_bytes_read          | select(.!=null) | tonumber] as $r |
    ($p|length) as $pl | ($r|length) as $rl |
    [
      (if $pl>0 then ($p|add)/$pl else 0 end),
      (if $rl>0 then ($r|add)/$rl else 0 end)
    ] | @tsv
  ' "$raw_file"
}

# Temperature distribution (includes initiator) -> JSON object like {"cold":3,"hot":2,"warm":5}
replica_temp_distribution_json() {
  local raw_file="$1"
  jq -c '
    [ .[] | .replica_temperature | select(.!=null) ]
    | group_by(.) | map({ (.[0]): (length) }) | add // {}
  ' "$raw_file"
}

# Initiator net_recv_bytes (raw, single number; 0 if missing)
initiator_net_recv_bytes_raw() {
  local raw_file="$1"
  jq -r '
    [ .[] | select(.is_initiator_node==1) | .replica_net_recv_bytes | select(.!=null) | tonumber ] as $a
    | (if ($a|length)>0 then $a[0] else 0 end)
  ' "$raw_file"
}

# Humanize a byte value (binary units).
human_bytes() {
  local bytes="$1"
  awk -v b="$bytes" '
    function fmt(x,u){ printf("%.2f %s", x, u) }
    BEGIN{
      if (b < 1024)            fmt(b, "B");
      else if (b < 1048576)    fmt(b/1024, "KiB");
      else if (b < 1073741824) fmt(b/1048576, "MiB");
      else                     fmt(b/1073741824, "GiB");
    }'
}

# Extract the initiator node’s pretty “rows/s total” string from a *pretty* stats JSON.
initiator_rps_pretty() {
  local pretty_file="$1"
  jq -r '
    map(select(.is_initiator_node==1 and .query_rows_per_sec!=null))
    | (.[0].query_rows_per_sec // empty)
  ' "$pretty_file"
}


# Pretty-print bytes/sec with dynamic units
pretty_bps() {
  local v=$1
  local units=("B/s" "KiB/s" "MiB/s" "GiB/s" "TiB/s")
  local i=0
  # use bc for floating division if needed
  while (( $(echo "$v >= 1024" | bc -l) )) && (( i < ${#units[@]}-1 )); do
    v=$(echo "$v/1024" | bc -l)
    ((i++))
  done
  printf "%.2f %s" "$v" "${units[$i]}"
}

# Pretty print rows/sec with words (million/billion/trillion)
pretty_rps() {
  local v="$1"
  awk -v n="$v" '
    function fmt(x,u){ printf("%.2f %s rows/s", x, u) }
    BEGIN{
      if (n < 1e6)       printf("%.0f rows/s", n);
      else if (n < 1e9)  fmt(n/1e6,  "million");
      else if (n < 1e12) fmt(n/1e9,  "billion");
      else               fmt(n/1e12, "trillion");
    }'
}





# ---------------------------------------
# Master summary preamble
# ---------------------------------------
{
  echo "{"
  echo "  \"date\": \"$DATE\","
  echo "  \"version\": \"$CH_VERSION\","
  echo "  \"csp\": \"$CSP\","
  echo "  \"region\": \"$REGION\","
  echo "  \"query_db\": \"$QUERY_DB\","
  echo "  \"query_file\": \"$(basename "$QUERY_FILE")\","
  echo "  \"ram_gb_per_node\": $RAM_GB_PER_NODE,"
  echo "  \"runs_per_combination\": $RUNS_PER_COMBINATION,"
  echo "  \"stats_group\": \"$STATS_GROUP\","
  echo "  \"node_list\": [$(echo "$NODE_LIST" | sed 's/ /, /g')],"
  echo "  \"cores_list\": [$(echo "$CORES_LIST" | sed 's/ /, /g')],"
  echo "  \"result_matrix\": {"
} > "$SUMMARY_FILE"

first_combo=true

# ---------------------------------------
# Matrix: for each (nodes x cores)
# ---------------------------------------
for NODES in $NODE_LIST; do
  echo "▶️  Node count: $NODES"
  for CORES in $CORES_LIST; do
    echo "   ➤ Cores: $CORES  ($RUNS_PER_COMBINATION runs)"

    COMBO_KEY="n${NODES}c${CORES}"
    COMBO_RESULTS=()
    COMBO_DIR="$RESULTS_DIR/stats/$STATS_GROUP/$COMBO_KEY"
    mkdir -p "$COMBO_DIR"

    if [[ "$DROP_CACHES" == "true" ]]; then
      drop_caches
    else
      echo "⚡️ Skipping cache drop (DROP_CACHES=$DROP_CACHES)"
    fi

    for ((i=1; i<=RUNS_PER_COMBINATION; i++)); do
      echo "      🔁 Run $i/$RUNS_PER_COMBINATION..."

      if [[ $i -eq 1 ]]; then
        enable_filesystem_cache=0   # first run = cold
      else
        enable_filesystem_cache=1   # subsequent runs = hot
      fi

      RUN_TS="$(date +%H%M%S)"
      LOG_COMMENT="benchM:${DATE}T${RUN_TS}-n${NODES}-c${CORES}-run${i}"

      t=$(run_with_time "$QUERY_SQL" "$NODES" "$CORES" "$enable_filesystem_cache" "$LOG_COMMENT")
      echo "         runtime: $t s"
      COMBO_RESULTS+=("$t")

      # Pretty + raw side-by-side into per-session folder
      dump_run_stats_pair "$LOG_COMMENT" "$COMBO_DIR/run_${i}"
    done

    # --- Decide cold/hot using "first run is cold" rule ---
    COUNT=${#COMBO_RESULTS[@]}

    # Cold = run #1 (first run)
    COLDEST="${COMBO_RESULTS[0]}"
    COLDEST_RUN=1

    # Hot = fastest among runs 2..N
    if (( COUNT > 1 )); then
      HOTTEST="${COMBO_RESULTS[1]}"
      HOTTEST_IDX=1
      for ((idx=2; idx<COUNT; idx++)); do
        val="${COMBO_RESULTS[$idx]}"
        awk -v a="$val" -v b="$HOTTEST" 'BEGIN{exit !(a<b)}' && { HOTTEST="$val"; HOTTEST_IDX="$idx"; }
      done
      HOTTEST_RUN=$((HOTTEST_IDX + 1))
    else
      # Only one run available; hot == cold
      HOTTEST="${COMBO_RESULTS[0]}"
      HOTTEST_RUN=1
    fi

    # Paths (relative) to the chosen run artifacts
    COLD_PRETTY_REL="stats/$STATS_GROUP/$COMBO_KEY/run_${COLDEST_RUN}_pretty.json"
    COLD_RAW_REL="stats/$STATS_GROUP/$COMBO_KEY/run_${COLDEST_RUN}_raw.json"
    HOT_PRETTY_REL="stats/$STATS_GROUP/$COMBO_KEY/run_${HOTTEST_RUN}_pretty.json"
    HOT_RAW_REL="stats/$STATS_GROUP/$COMBO_KEY/run_${HOTTEST_RUN}_raw.json"

    # HOTTEST_AVG = average of all non-cold runs (runs 2..N)
    if (( COUNT > 1 )); then
      SUM_HOT=$(printf "%s\n" "${COMBO_RESULTS[@]:1}" | awk '{s+=$1} END{print s+0}')
      HOTTEST_AVG=$(awk -v s="$SUM_HOT" -v c="$COUNT" 'BEGIN{printf "%.6f", s/(c-1)}')
    else
      HOTTEST_AVG=null
    fi

    echo "      ❄️  Cold (first run): $COLDEST (run #$COLDEST_RUN -> $COLD_PRETTY_REL)"
    echo "      🔥  Hot  (fastest among runs 2..$COUNT): $HOTTEST (run #$HOTTEST_RUN -> $HOT_PRETTY_REL)"
    echo "      🔥  Hot avg (runs 2..$COUNT): $HOTTEST_AVG"

    # --- Aggregated extras (from RAW + PRETTY of chosen runs) ---

    # EXCL initiator
    read COLD_AVG_MEM_EXCL COLD_AVG_READ_EXCL COLD_AVG_NET_SENT_EXCL COLD_SUM_NET_SENT_EXCL COLD_AVG_PCT_EXCL < <(raw_aggregates_excl_initiator "$RESULTS_DIR/$COLD_RAW_REL")
    read HOT_AVG_MEM_EXCL  HOT_AVG_READ_EXCL  HOT_AVG_NET_SENT_EXCL  HOT_SUM_NET_SENT_EXCL  HOT_AVG_PCT_EXCL  < <(raw_aggregates_excl_initiator "$RESULTS_DIR/$HOT_RAW_REL")

    # Humanize excl-initiator values
    COLD_AVG_MEM_EXCL_H="$(human_bytes "$COLD_AVG_MEM_EXCL")"
    COLD_AVG_NET_SENT_EXCL_H="$(human_bytes "$COLD_AVG_NET_SENT_EXCL")"
    COLD_SUM_NET_SENT_EXCL_H="$(human_bytes "$COLD_SUM_NET_SENT_EXCL")"

    HOT_AVG_MEM_EXCL_H="$(human_bytes "$HOT_AVG_MEM_EXCL")"
    HOT_AVG_NET_SENT_EXCL_H="$(human_bytes "$HOT_AVG_NET_SENT_EXCL")"
    HOT_SUM_NET_SENT_EXCL_H="$(human_bytes "$HOT_SUM_NET_SENT_EXCL")"

    # INCLUDING initiator: avg pct + avg bytes_read
    read COLD_AVG_PCT_INCL COLD_AVG_BYTESREAD_INCL < <(avg_pct_and_bytesread_incl_initiator "$RESULTS_DIR/$COLD_RAW_REL")
    read HOT_AVG_PCT_INCL  HOT_AVG_BYTESREAD_INCL  < <(avg_pct_and_bytesread_incl_initiator "$RESULTS_DIR/$HOT_RAW_REL")

    COLD_AVG_BYTESREAD_INCL_H="$(human_bytes "$COLD_AVG_BYTESREAD_INCL")"
    HOT_AVG_BYTESREAD_INCL_H="$(human_bytes "$HOT_AVG_BYTESREAD_INCL")"

    COLD_AVG_PCT_VAL="$(printf '%.2f' "$COLD_AVG_PCT_INCL")"
    HOT_AVG_PCT_VAL="$(printf '%.2f' "$HOT_AVG_PCT_INCL")"
    COLD_AVG_PCT_HUMAN="${COLD_AVG_PCT_VAL} %"
    HOT_AVG_PCT_HUMAN="${HOT_AVG_PCT_VAL} %"

    # Round numeric (non-human) to 2 decimals
    COLD_AVG_MEM_EXCL_NUM="$(printf '%.2f' "$COLD_AVG_MEM_EXCL")"
    COLD_AVG_NET_SENT_EXCL_NUM="$(printf '%.2f' "$COLD_AVG_NET_SENT_EXCL")"
    COLD_SUM_NET_SENT_EXCL_NUM="$(printf '%.2f' "$COLD_SUM_NET_SENT_EXCL")"
    COLD_AVG_BYTESREAD_INCL_NUM="$(printf '%.2f' "$COLD_AVG_BYTESREAD_INCL")"

    HOT_AVG_MEM_EXCL_NUM="$(printf '%.2f' "$HOT_AVG_MEM_EXCL")"
    HOT_AVG_NET_SENT_EXCL_NUM="$(printf '%.2f' "$HOT_AVG_NET_SENT_EXCL")"
    HOT_SUM_NET_SENT_EXCL_NUM="$(printf '%.2f' "$HOT_SUM_NET_SENT_EXCL")"
    HOT_AVG_BYTESREAD_INCL_NUM="$(printf '%.2f' "$HOT_AVG_BYTESREAD_INCL")"

    # Temperature distribution (includes initiator)
    COLD_TEMP_JSON="$(replica_temp_distribution_json "$RESULTS_DIR/$COLD_RAW_REL")"
    HOT_TEMP_JSON="$(replica_temp_distribution_json "$RESULTS_DIR/$HOT_RAW_REL")"

    # Initiator net recv (bytes + human)
    COLD_INIT_NET_RECV="$(initiator_net_recv_bytes_raw "$RESULTS_DIR/$COLD_RAW_REL")"
    HOT_INIT_NET_RECV="$(initiator_net_recv_bytes_raw "$RESULTS_DIR/$HOT_RAW_REL")"
    COLD_INIT_NET_RECV_NUM="$(printf '%.2f' "$COLD_INIT_NET_RECV")"
    HOT_INIT_NET_RECV_NUM="$(printf '%.2f' "$HOT_INIT_NET_RECV")"
    COLD_INIT_NET_RECV_H="$(human_bytes "$COLD_INIT_NET_RECV")"
    HOT_INIT_NET_RECV_H="$(human_bytes "$HOT_INIT_NET_RECV")"

    # Initiator pretty RPS
    COLD_QUERY_RPS_PRETTY="$(initiator_rps_pretty "$RESULTS_DIR/$COLD_PRETTY_REL")"
    HOT_QUERY_RPS_PRETTY="$(initiator_rps_pretty "$RESULTS_DIR/$HOT_PRETTY_REL")"


    # ---------- new: compute bytes/sec metrics for cold/hot ----------

    # Resolve chosen run file paths
    COLD_RAW_PATH="$RESULTS_DIR/$COLD_RAW_REL"
    HOT_RAW_PATH="$RESULTS_DIR/$HOT_RAW_REL"
    COLD_PRETTY_PATH="$RESULTS_DIR/$COLD_PRETTY_REL"
    HOT_PRETTY_PATH="$RESULTS_DIR/$HOT_PRETTY_REL"

    # --- avg_replica_bps_* from RAW (numeric), then pretty-print ---
    avg_replica_bps_cold=$(
      jq '[.[].replica_bytes_per_sec_total? | select(.!=null) | tonumber]
          | if length>0 then (add/length) else 0 end' \
         "$COLD_RAW_PATH"
    )
    avg_replica_bps_hot=$(
      jq '[.[].replica_bytes_per_sec_total? | select(.!=null) | tonumber]
          | if length>0 then (add/length) else 0 end' \
         "$HOT_RAW_PATH"
    )

    avg_replica_bps_cold_human="$(pretty_bps "$avg_replica_bps_cold")"
    avg_replica_bps_hot_human="$(pretty_bps "$avg_replica_bps_hot")"

    # --- initiator_bps_* from PRETTY (already human formatted) ---
    initiator_bps_cold_pretty=$(
      jq -r 'map(select(.is_initiator_node==1 and .query_bytes_per_sec!=null))
             | (.[0].query_bytes_per_sec // empty)' \
         "$COLD_PRETTY_PATH"
    )
    initiator_bps_hot_pretty=$(
      jq -r 'map(select(.is_initiator_node==1 and .query_bytes_per_sec!=null))
             | (.[0].query_bytes_per_sec // empty)' \
         "$HOT_PRETTY_PATH"
    )

    # --- avg_replica_rows_per_sec from RAW (numeric), then pretty-print ---
    avg_replica_rps_cold=$(
      jq '[.[].replica_rows_per_sec_total? | select(.!=null) | tonumber]
          | if length>0 then (add/length) else 0 end' \
         "$RESULTS_DIR/$COLD_RAW_REL"
    )
    avg_replica_rps_hot=$(
      jq '[.[].replica_rows_per_sec_total? | select(.!=null) | tonumber]
          | if length>0 then (add/length) else 0 end' \
         "$RESULTS_DIR/$HOT_RAW_REL"
    )

    avg_replica_rps_cold_human="$(pretty_rps "$avg_replica_rps_cold")"
    avg_replica_rps_hot_human="$(pretty_rps "$avg_replica_rps_hot")"


    # Per-combination mini-summary (optional artifact)
    COMBO_SUMMARY="$RESULTS_DIR/${COMBO_KEY}_${DATE}_${TIME}.json"
    {
      echo "{"
      echo "  \"date\": \"$DATE\","
      echo "  \"version\": \"$CH_VERSION\","
      echo "  \"csp\": \"$CSP\","
      echo "  \"region\": \"$REGION\","
      echo "  \"query_db\": \"$QUERY_DB\","
      echo "  \"query_file\": \"$(basename "$QUERY_FILE")\","
      echo "  \"nodes\": $NODES,"
      echo "  \"cpu_cores\": $CORES,"
      echo "  \"ram_gb_per_node\": $RAM_GB_PER_NODE,"
      echo "  \"runs\": [$(IFS=,; echo "${COMBO_RESULTS[*]}")],"
      echo "  \"timing\": { \"cold\": $COLDEST, \"hot\": $HOTTEST, \"hot_avg\": $HOTTEST_AVG },"
      echo "  \"files\": {"
      echo "    \"cold_pretty\": \"$COLD_PRETTY_REL\","
      echo "    \"cold_raw\": \"$COLD_RAW_REL\","
      echo "    \"hot_pretty\": \"$HOT_PRETTY_REL\","
      echo "    \"hot_raw\": \"$HOT_RAW_REL\""
      echo "  },"
      echo "  \"cold_stats\": {"
      echo "    \"avg_replica_pct\": { \"value\": $COLD_AVG_PCT_VAL, \"human\": \"$COLD_AVG_PCT_HUMAN\" },"
      echo "    \"replica_temperature_distribution\": $COLD_TEMP_JSON,"
      echo "    \"avg_replica_memory_excl_initiator\": { \"bytes\": $COLD_AVG_MEM_EXCL_NUM, \"human\": \"$COLD_AVG_MEM_EXCL_H\" },"
      echo "    \"avg_replica_bytes_read\": { \"bytes\": $COLD_AVG_BYTESREAD_INCL_NUM, \"human\": \"$COLD_AVG_BYTESREAD_INCL_H\" },"
      echo "    \"avg_replica_net_sent_excl_initiator\": { \"bytes\": $COLD_AVG_NET_SENT_EXCL_NUM, \"human\": \"$COLD_AVG_NET_SENT_EXCL_H\" },"
      echo "    \"sum_replica_net_sent_excl_initiator\": { \"bytes\": $COLD_SUM_NET_SENT_EXCL_NUM, \"human\": \"$COLD_SUM_NET_SENT_EXCL_H\" },"
      echo "    \"initiator_net_recv\": { \"bytes\": $COLD_INIT_NET_RECV_NUM, \"human\": \"$COLD_INIT_NET_RECV_H\" },"
      echo "    \"avg_replica_bytes_per_sec\": { \"value\": $avg_replica_bps_cold, \"human\": \"$avg_replica_bps_cold_human\" },"
      echo "    \"avg_replica_rows_per_sec\": { \"value\": $avg_replica_rps_cold, \"human\": \"$avg_replica_rps_cold_human\" },"
      echo "    \"initiator_bytes_per_sec\": \"${initiator_bps_cold_pretty}\","
      echo "    \"initiator_rows_per_sec\": \"${COLD_QUERY_RPS_PRETTY}\""
      echo "  },"
      echo "  \"hot_stats\": {"
      echo "    \"avg_replica_pct\": { \"value\": $HOT_AVG_PCT_VAL, \"human\": \"$HOT_AVG_PCT_HUMAN\" },"
      echo "    \"replica_temperature_distribution\": $HOT_TEMP_JSON,"
      echo "    \"avg_replica_memory_excl_initiator\": { \"bytes\": $HOT_AVG_MEM_EXCL_NUM, \"human\": \"$HOT_AVG_MEM_EXCL_H\" },"
      echo "    \"avg_replica_bytes_read\": { \"bytes\": $HOT_AVG_BYTESREAD_INCL_NUM, \"human\": \"$HOT_AVG_BYTESREAD_INCL_H\" },"
      echo "    \"avg_replica_net_sent_excl_initiator\": { \"bytes\": $HOT_AVG_NET_SENT_EXCL_NUM, \"human\": \"$HOT_AVG_NET_SENT_EXCL_H\" },"
      echo "    \"sum_replica_net_sent_excl_initiator\": { \"bytes\": $HOT_SUM_NET_SENT_EXCL_NUM, \"human\": \"$HOT_SUM_NET_SENT_EXCL_H\" },"
      echo "    \"initiator_net_recv\": { \"bytes\": $HOT_INIT_NET_RECV_NUM, \"human\": \"$HOT_INIT_NET_RECV_H\" },"
      echo "    \"avg_replica_bytes_per_sec\": { \"value\": $avg_replica_bps_hot, \"human\": \"$avg_replica_bps_hot_human\" },"
      echo "    \"avg_replica_rows_per_sec\": { \"value\": $avg_replica_rps_hot, \"human\": \"$avg_replica_rps_hot_human\" },"
      echo "    \"initiator_bytes_per_sec\": \"${initiator_bps_hot_pretty}\","
      echo "    \"initiator_rows_per_sec\": \"${HOT_QUERY_RPS_PRETTY}\""
      echo "  }"
      echo "}"
    } > "$COMBO_SUMMARY"

    # Append into master summary
    if [ "$first_combo" = true ]; then
      first_combo=false
      sep=""
    else
      sep=","
    fi
    {
      echo "$sep"
      echo "    \"$COMBO_KEY\": {"
      echo "      \"timing\": { \"cold\": $COLDEST, \"hot\": $HOTTEST, \"hot_avg\": $HOTTEST_AVG },"
      echo "      \"runs\": [$(IFS=,; echo "${COMBO_RESULTS[*]}")],"
      echo "      \"files\": {"
      echo "        \"cold_pretty\": \"$COLD_PRETTY_REL\","
      echo "        \"cold_raw\": \"$COLD_RAW_REL\","
      echo "        \"hot_pretty\": \"$HOT_PRETTY_REL\","
      echo "        \"hot_raw\": \"$HOT_RAW_REL\""
      echo "      },"
      echo "      \"cold_stats\": {"
      echo "        \"avg_replica_pct\": { \"value\": $COLD_AVG_PCT_VAL, \"human\": \"$COLD_AVG_PCT_HUMAN\" },"
      echo "        \"replica_temperature_distribution\": $COLD_TEMP_JSON,"
      echo "        \"avg_replica_memory_excl_initiator\": { \"bytes\": $COLD_AVG_MEM_EXCL_NUM, \"human\": \"$COLD_AVG_MEM_EXCL_H\" },"
      echo "        \"avg_replica_bytes_read\": { \"bytes\": $COLD_AVG_BYTESREAD_INCL_NUM, \"human\": \"$COLD_AVG_BYTESREAD_INCL_H\" },"
      echo "        \"avg_replica_net_sent_excl_initiator\": { \"bytes\": $COLD_AVG_NET_SENT_EXCL_NUM, \"human\": \"$COLD_AVG_NET_SENT_EXCL_H\" },"
      echo "        \"sum_replica_net_sent_excl_initiator\": { \"bytes\": $COLD_SUM_NET_SENT_EXCL_NUM, \"human\": \"$COLD_SUM_NET_SENT_EXCL_H\" },"
      echo "        \"initiator_net_recv\": { \"bytes\": $COLD_INIT_NET_RECV_NUM, \"human\": \"$COLD_INIT_NET_RECV_H\" },"
      echo "        \"avg_replica_bytes_per_sec\": { \"value\": $avg_replica_bps_cold, \"human\": \"$avg_replica_bps_cold_human\" },"
      echo "        \"avg_replica_rows_per_sec\": { \"value\": $avg_replica_rps_cold, \"human\": \"$avg_replica_rps_cold_human\" },"
      echo "        \"initiator_bytes_per_sec\": \"${initiator_bps_cold_pretty}\","
      echo "        \"initiator_rows_per_sec\": \"${COLD_QUERY_RPS_PRETTY}\""
      echo "      },"
      echo "      \"hot_stats\": {"
      echo "        \"avg_replica_pct\": { \"value\": $HOT_AVG_PCT_VAL, \"human\": \"$HOT_AVG_PCT_HUMAN\" },"
      echo "        \"replica_temperature_distribution\": $HOT_TEMP_JSON,"
      echo "        \"avg_replica_memory_excl_initiator\": { \"bytes\": $HOT_AVG_MEM_EXCL_NUM, \"human\": \"$HOT_AVG_MEM_EXCL_H\" },"
      echo "        \"avg_replica_bytes_read\": { \"bytes\": $HOT_AVG_BYTESREAD_INCL_NUM, \"human\": \"$HOT_AVG_BYTESREAD_INCL_H\" },"
      echo "        \"avg_replica_net_sent_excl_initiator\": { \"bytes\": $HOT_AVG_NET_SENT_EXCL_NUM, \"human\": \"$HOT_AVG_NET_SENT_EXCL_H\" },"
      echo "        \"sum_replica_net_sent_excl_initiator\": { \"bytes\": $HOT_SUM_NET_SENT_EXCL_NUM, \"human\": \"$HOT_SUM_NET_SENT_EXCL_H\" },"
      echo "        \"initiator_net_recv\": { \"bytes\": $HOT_INIT_NET_RECV_NUM, \"human\": \"$HOT_INIT_NET_RECV_H\" },"
      echo "        \"avg_replica_bytes_per_sec\": { \"value\": $avg_replica_bps_hot, \"human\": \"$avg_replica_bps_hot_human\" },"
      echo "        \"avg_replica_rows_per_sec\": { \"value\": $avg_replica_rps_hot, \"human\": \"$avg_replica_rps_hot_human\" },"
      echo "        \"initiator_bytes_per_sec\": \"${initiator_bps_hot_pretty}\","
      echo "        \"initiator_rows_per_sec\": \"${HOT_QUERY_RPS_PRETTY}\""
      echo "      }"
      echo "    }"
    } >> "$SUMMARY_FILE"

  done
done

# ---------------------------------------
# Close master summary
# ---------------------------------------
{
  echo ""
  echo "  }"
  echo "}"
} >> "$SUMMARY_FILE"

# Convenience: "latest" symlink to this session’s stats
ln -sfn "$RESULTS_DIR/stats/$STATS_GROUP" "$RESULTS_DIR/stats/latest"

echo "✅ Done. Master summary: $SUMMARY_FILE"
echo "📁 Stats session folder: $RESULTS_DIR/stats/$STATS_GROUP (also at $RESULTS_DIR/stats/latest)"