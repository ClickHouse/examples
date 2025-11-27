#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------
# Enrich ClickBench benchmark results with Databricks costs
# using sql_serverless_compute.json pricing data.
#
# Usage:
#   ./enrich_v2.sh <clickbench_json> <pricing_json> <output_json> \
#       [--cloud <val>] [--region <val>] [--plan <val>]
#
# Example:
#   ./enrich_v2.sh clickbench/results/clickbench_2X-Small.json \
#                  pricings/sql_serverless_compute.json \
#                  results/clickbench_2X-Small_enriched_v2.json \
#                  --cloud aws --region us-east-1 --plan premium
# ---------------------------------------------

# Default parameters
CLOUD="aws"
REGION="us-east-1"
PLAN="premium"

# --- Argument parsing ---
if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <clickbench_json> <pricing_json> <output_json> [--cloud <val>] [--region <val>] [--plan <val>]" >&2
  exit 1
fi

BENCH_FILE="$1"
PRICING_FILE="$2"
OUT_FILE="$3"
shift 3

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cloud) CLOUD="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    --plan) PLAN="$2"; shift 2 ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# --- Checks ---
if ! command -v jq >/dev/null 2>&1; then
  echo "❌ jq is required but not installed. Try: sudo apt install jq" >&2
  exit 1
fi

if [ ! -f "$BENCH_FILE" ]; then
  echo "❌ Benchmark file not found: $BENCH_FILE" >&2
  exit 1
fi

if [ ! -f "$PRICING_FILE" ]; then
  echo "❌ Pricing file not found: $PRICING_FILE" >&2
  exit 1
fi

# Ensure output directory exists
OUT_DIR=$(dirname "$OUT_FILE")
mkdir -p "$OUT_DIR"

# Extract instance (cluster_size) from ClickBench file
MACHINE=$(jq -r '.cluster_size' "$BENCH_FILE")
if [ -z "$MACHINE" ] || [ "$MACHINE" = "null" ]; then
  echo "❌ Could not read .cluster_size field from $BENCH_FILE" >&2
  exit 1
fi

echo "→ Enriching ClickBench results for ${MACHINE}"
echo "  Cloud : ${CLOUD}"
echo "  Region: ${REGION}"
echo "  Plan  : ${PLAN}"
echo "  Input : ${BENCH_FILE}"
echo "  Pricing: ${PRICING_FILE}"
echo "  Output: ${OUT_FILE}"
echo

# --- jq enrichment logic ---
jq -s \
  --arg cloud "$CLOUD" \
  --arg region "$REGION" \
  --arg plan "$PLAN" '
  .[0] as $bench | .[1] as $pricing |

  # instance name is in ClickBench .cluster_size (e.g. "2X-Small")
  ($bench.cluster_size) as $machine |

  # select pricing block matching input args
  ($pricing.pricing[]
    | select(.cloud == $cloud and .region == $region and .plan == $plan)) as $block |

  # pick the matching instance definition
  ($block.instances[] | select(.name == $machine)) as $inst |

  # compute price components
  ($block.dbu_price_per_hour) as $price_per_dbu_hour |
  ($inst.dbu_per_hour)        as $dbu_per_hour     |

  # storage pricing is nested under .storage
  ($block.storage.storage // null) as $storage_price |
  ($block.storage.storage_price_unit // null) as $storage_unit |

  # data size in bytes from the benchmark file
  ($bench.data_size // null) as $data_size |

  # derived storage cost + breakdown (if we have all the pieces)
  (if ($storage_price != null and $storage_unit != null and $data_size != null)
   then
     ($data_size * $storage_price / $storage_unit) as $sc |
     {
       storage_cost: $sc,
       storage_costs: [
         {
           type: "data",
           bytes: $data_size,
           price_per_unit: $storage_price,
           unit_bytes: $storage_unit,
           estimated_cost: $sc
         }
       ]
     }
   else
     {
       storage_cost: 0,
       storage_costs: []
     }
   end) as $stor |

  $bench + {
    costs: [
      {
        tier: $plan,
        provider: $cloud,
        service: $pricing.service,
        cloud: $cloud,
        region: $region,
        warehouse_size: $inst.name,

        # carry through the data size and attach storage info
        data_size: $data_size
      }
      + $stor
      + {
        compute_costs:
          ($bench.result
           | map(
               map(
                 if . == null then null
                 else (. / 3600.0 * $dbu_per_hour * $price_per_dbu_hour)
                 end
               )
             )),
        pricing_base: {
          dbu_per_hour:       $dbu_per_hour,
          dbu_price_per_hour: $price_per_dbu_hour
        }
      }
    ]
  }
' "$BENCH_FILE" "$PRICING_FILE" > "$OUT_FILE"

# --- Total compute cost summary ---
TOTAL_COST=$(jq '[.costs[0].compute_costs[][]] | add' "$OUT_FILE")

printf "\n✅ Done! Wrote enriched result to: %s\n" "$OUT_FILE"
printf "💰 Total estimated compute cost (all runs): \$%.4f\n" "$TOTAL_COST"