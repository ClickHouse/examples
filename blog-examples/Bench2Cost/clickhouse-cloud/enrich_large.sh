#!/usr/bin/env bash
set -euo pipefail

# -----------------------------
# Args
# -----------------------------
if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <results_dir> <output_dir>"
  echo "  <results_dir> : directory with *.parallel_replicas.json files"
  echo "  <output_dir>  : where enriched JSON files will be written"
  exit 1
fi

RESULTS_DIR="$1"
OUTPUT_DIR="$2"


mkdir -p "$OUTPUT_DIR"
shopt -s nullglob
files=( "$RESULTS_DIR"/*.parallel_replicas.json )
echo "Found ${#files[@]} file(s)."

TIERS_JSON='[
  {"name":"Basic","compute":0.2181100,"compute_price_unit":8,"storage":25.30,"storage_price_unit":1000000000000},
  {"name":"Scale","compute":0.29846,"compute_price_unit":8,"storage":25.30,"storage_price_unit":1000000000000},
  {"name":"Enterprise","compute":0.3903,"compute_price_unit":8,"storage":25.30,"storage_price_unit":1000000000000}
]'

for in in "${files[@]}"; do
  base="$(basename "$in")"
  out="$OUTPUT_DIR/$base"
  echo " -> $base"

  jq --arg provider aws --arg region us-east-1 --argjson tiers "$TIERS_JSON" '
    def tosec:
      if type=="number" then . else (try tonumber catch 0) // 0 end;

    .provider = $provider
    | .region  = $region
    | (if has("cluster_size") then (.cluster_size|tonumber) else 1 end) as $cluster
    | (if has("data_size") and (.data_size != null) then (.data_size|tonumber) else 0 end) as $bytes
    | ( if has("memory_size") and (.memory_size != null)
        then (.memory_size|tonumber)
        else ((.machine|tostring) | gsub("[^0-9\\.]";"") | if length>0 then tonumber else 0 end)
      end ) as $mem_gib
    | (.result // []) as $res
    | . + {
        costs: (
          $tiers | map(
            . as $tier
            | (($tier.storage / $tier.storage_price_unit)) as $price_per_byte
            | (
                [ $res[] |
                  [ .[] | (tosec * ($tier.compute / 3600.0) * ($mem_gib / $tier.compute_price_unit) * $cluster) ]
                ]
              ) as $compute_costs
            | ($bytes * $price_per_byte) as $storage_cost_value
            | {
                tier: $tier.name,
                provider: $provider,
                region: $region,
                compute_costs: $compute_costs,
                storage_cost: $storage_cost_value
              }
          )
        )
      }
  ' "$in" > "$out"

  echo "    saved → $out"
done

echo "Done. Outputs in: $OUTPUT_DIR"