#!/usr/bin/env bash
set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "❌ jq is required"; exit 1; }
command -v clickhouse >/dev/null 2>&1 || { echo "❌ clickhouse client not found"; exit 1; }

# -----------------------------
# ClickHouse client wrapper
# -----------------------------
CH_HOST="${CH_HOST:-localhost}"
CH_USER="${CH_USER:-default}"
CH_PASSWORD="${CH_PASSWORD-}"          # may be empty / unset
CH_SECURE="${CH_SECURE:-}"             # set to true/1/yes to enable --secure

CH_SECURE_FLAG=""
if [[ "${CH_SECURE,,}" =~ ^(1|true|yes)$ ]]; then
  CH_SECURE_FLAG="--secure"
fi

CH_PASSWORD_PART=""
if [[ -n "${CH_PASSWORD}" ]]; then
  CH_PASSWORD_PART="--password ${CH_PASSWORD}"
fi

CH_CLIENT="clickhouse client --host ${CH_HOST} --user ${CH_USER} ${CH_PASSWORD_PART} ${CH_SECURE_FLAG}"

# -----------------------------
# Args
# -----------------------------
RESET=false
if [[ "${1:-}" == "--reset" ]]; then
  RESET=true
  shift
fi

if [[ $# -lt 2 || $# -gt 4 ]]; then
  echo "Usage: $0 [--reset] <database> <table> [root_dir] [results_subdir]"
  echo "  root_dir defaults to parent directory (..)."
  echo "  results_subdir defaults to 'results'."
  exit 1
fi

DB="$1"
TABLE="$2"
ROOT="${3:-..}"
RESULTS_SUBDIR="${4:-results}"

# -----------------------------
# Ensure DB/table exist
# -----------------------------
$CH_CLIENT --query "CREATE DATABASE IF NOT EXISTS ${DB}"

if $RESET; then
  echo "⚠️  Dropping and recreating table ${DB}.${TABLE}"
  $CH_CLIENT --query "DROP TABLE IF EXISTS ${DB}.${TABLE}"
fi

# FINAL single-table schema (tiny row count; simple ORDER BY)
$CH_CLIENT --query "
CREATE TABLE IF NOT EXISTS ${DB}.${TABLE}
(
  system            LowCardinality(String),
  date              Date,
  machine           LowCardinality(String),
  cluster_size      LowCardinality(String),

  provider          Nullable(String),
  region            Nullable(String),
  tier              Nullable(String),

  compute_model     Nullable(String),
  pricing_variant   Nullable(String),
  billing_period    Nullable(String),

  proprietary       LowCardinality(String),
  tuned             LowCardinality(String),
  comment           String,
  tags              Array(LowCardinality(String)),
  load_time         UInt32,
  data_size         UInt64,

  -- performance: 3 runs per query
  result            Array(Tuple(Nullable(Float64), Nullable(Float64), Nullable(Float64))),

  -- costs per run per query (shape mirrors result)
  compute_costs     Array(Tuple(Nullable(Float64), Nullable(Float64), Nullable(Float64))),

  -- legacy/default flat storage cost (always one number)
  storage_cost      Float64,

  -- generic structured storage costs: ('model/term/period', estimated_cost)
  storage_costs     Array(Tuple(String, Float64))
)
ENGINE = MergeTree
ORDER BY (system, date, machine, cluster_size);
"

# -----------------------------
# jq program: build VALUES tuples from each .costs[] entry
# -----------------------------
JQ_PROG="$(mktemp)"
trap 'rm -f "$JQ_PROG"' EXIT

cat >"$JQ_PROG" <<'JQ'
# ---------- Helpers to build SQL literals ----------
def sql_str(s):
  "'" + ((s // "") | tostring | gsub("'"; "\\'")) + "'";

def sql_nullable_str(s):
  if (s == null) or (s == "") then "NULL" else sql_str(s) end;

def sql_date(d):
  "toDate(" + sql_str(d // "1970-01-01") + ")";

def arr_str(arr):
  "[" + (arr | map(sql_str(.)) | join(",")) + "]";

# Array(Tuple(Nullable(Float64), Nullable(Float64), Nullable(Float64)))
def tuple3_array(a):
  "[" + (a
         | map([
             (.[0] // null),
             (.[1] // null),
             (.[2] // null)
           ]
           | map(if .==null then "NULL" else tostring end)
           | "(" + (join(",")) + ")"
         )
         | join(",")
       ) + "]";

# Array(Tuple(String, Float64)) for storage_costs where label is "model/term/period"
def storage_label_cost_array(a):
  "[" + (
    a
    | map(
        ( ((.model // "") + "/" + (.term // "") + "/" + (.period // "")) | gsub(" "; "") ) as $lbl
        | "(" + sql_str($lbl) + "," + ((.estimated_cost // 0) | tostring) + ")"
      )
    | join(",")
  ) + "]";

# ---------- Transform ----------
. as $r
| (sql_str($r.system)) as $system_
| (sql_date($r.date)) as $date_
| (sql_str($r.machine)) as $machine_
| (sql_str(($r.cluster_size | tostring))) as $cluster_size_

| (sql_nullable_str($r.provider)) as $provider_doc_
| (sql_nullable_str($r.region))   as $region_doc_
| (sql_nullable_str(null))        as $tier_doc_

| (sql_nullable_str(null)) as $compute_model_doc_
| (sql_nullable_str(null)) as $pricing_variant_doc_
| (sql_nullable_str(null)) as $billing_period_doc_

| (sql_str($r.proprietary // "")) as $proprietary_
| (sql_str($r.tuned // ""))       as $tuned_
| (sql_str($r.comment // ""))     as $comment_
| (arr_str(($r.tags // [] | map(tostring)))) as $tags_
| (($r.load_time // 0)|tostring)  as $load_time_
| (($r.data_size // 0)|tostring)  as $data_size_
| tuple3_array($r.result // [])   as $result_

# Build rows from .costs[]
| (($r.costs // []) | map(
    . as $c
    | (sql_nullable_str($c.provider // $r.provider)) as $provider_
    | (sql_nullable_str($c.region))   as $region_
    | (sql_nullable_str($c.tier))     as $tier_

    | (sql_nullable_str($c.compute_model))   as $compute_model_
    | (sql_nullable_str($c.pricing_variant)) as $pricing_variant_
    | (sql_nullable_str($c.billing_period))  as $billing_period_

    | tuple3_array($c.compute_costs // []) as $compute_costs_

    # ------- storage_cost selection with clear scopes -------
    | ($c.storage_cost // null) as $sc
    | ($c.storage_costs // [])  as $scs
    | ($scs | map(select((.model // "")=="physical" and (.term // "")=="active" and (.period // "")=="monthly"))) as $bqdef
    | (
        if $sc != null then $sc
        else
          if ($bqdef | length) > 0 then ($bqdef[0].estimated_cost // 0)
          else if ($scs | length) > 0 then ($scs[0].estimated_cost // 0)
               else 0
               end
          end
        end
      ) as $storage_cost_num
    | ($storage_cost_num | tostring) as $storage_cost_num_

    | storage_label_cost_array($scs) as $storage_costs_arr_

    # Emit VALUES tuple
    | "("
      + $system_ + "," + $date_ + "," + $machine_ + "," + $cluster_size_ + ","
      + $provider_ + "," + $region_ + "," + $tier_ + ","
      + $compute_model_ + "," + $pricing_variant_ + "," + $billing_period_ + ","
      + $proprietary_ + "," + $tuned_ + "," + $comment_ + "," + $tags_ + ","
      + $load_time_ + "," + $data_size_ + "," + $result_ + ","
      + $compute_costs_ + "," + $storage_cost_num_ + "," + $storage_costs_arr_
    + ")"
  )) as $rows
| ($rows | if (length)>0 then join(",") else empty end)
JQ

# -----------------------------
# Scan and ingest JSON files
# -----------------------------
echo "Scanning ${ROOT} for */${RESULTS_SUBDIR}/*.json …"
found_any=false

while IFS= read -r -d '' f; do
  found_any=true
  echo "→ Ingesting: $f"

  if ! values_sql="$(jq -r -f "$JQ_PROG" "$f")"; then
    echo "   ⚠️  jq failed on: $f" >&2
    continue
  fi

  if [[ -z "${values_sql}" ]]; then
    echo "   ⏭️  No costs[] entries; skipping"
    continue
  fi

  if ! $CH_CLIENT --query "
      INSERT INTO ${DB}.${TABLE} (
        system, date, machine, cluster_size,
        provider, region, tier,
        compute_model, pricing_variant, billing_period,
        proprietary, tuned, comment, tags,
        load_time, data_size, result,
        compute_costs, storage_cost, storage_costs
      )
      VALUES ${values_sql};
  " </dev/null; then
    echo "   ⚠️  Failed: $f" >&2
  else
    echo "   ✅ ok"
  fi
done < <(
  find "$ROOT" -mindepth 2 -maxdepth 3 -type f \
       -path "*/${RESULTS_SUBDIR}/*.json" \
       -print0 | sort -z
)


if ! $found_any; then
  echo "No ${RESULTS_SUBDIR}/*.json files found under ${ROOT}"
else
  echo "✅ Done."
fi