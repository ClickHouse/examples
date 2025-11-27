#!/usr/bin/env bash
# BigQuery enrich script (serverless, hardened)
# Usage:
#   ./enrich.sh <result.json> <serverless_pricing.json> [region=us-east1] [output=enriched.json]
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq not found in PATH. Please install jq." >&2
  exit 1
fi

if [ "$#" -lt 2 ] || [ "$#" -gt 4 ]; then
  echo "Usage: $0 <result.json> <serverless_pricing.json> [region=us-east1] [output=enriched.json]" >&2
  exit 1
fi

RESULT_JSON="$1"
PRICING_JSON="$2"
REGION="${3:-us-east1}"
OUTPUT="${4:-enriched.json}"

[ -f "$RESULT_JSON" ] || { echo "Result file not found: $RESULT_JSON" >&2; exit 1; }
[ -f "$PRICING_JSON" ] || { echo "Pricing file not found: $PRICING_JSON" >&2; exit 1; }

jq -n \
  --slurpfile res "$RESULT_JSON" \
  --slurpfile price "$PRICING_JSON" \
  --arg region "$REGION" '
  # Aliases
  ($res[0]) as $r |
  ($price[0]) as $p |

  # Helpers
  def isobj: type == "object";
  def isarr: type == "array";

  def obj_entries(x):
    if (x|type) == "object" then x|to_entries else [] end;

  def map2d(arr; rate):
    (if (arr|type)=="array" then arr else [] end)
    | map( if (.|type)=="array" then
             map( if .==null then null else (. * rate) end )
           else [] end );

  def storage_entries(monthly; model):
    (obj_entries(monthly)
     | map({model:model, term:.key, base:.value})) // [];

  def storage_costs(p; region; bytes):
    (p.regions[region].pricing_storage // {}) as $ps |
    ( ($ps.logical // {}) | .monthly // {} ) as $logical_m |
    ( ($ps.physical // {}) | .monthly // {} ) as $physical_m |
    ( storage_entries($logical_m; "logical") + storage_entries($physical_m; "physical") )
    | map(
        . as $x
        | if ($x.base|type)=="object" and ($x.base.price_unit_bytes? // 0) != 0 then
            {
              model: $x.model,
              term: $x.term,
              period: "monthly",
              price_per_byte: ($x.base.price_usd / $x.base.price_unit_bytes),
              bytes: bytes,
              estimated_cost: (bytes * ($x.base.price_usd / $x.base.price_unit_bytes)),
              pricing_base: {
                price_usd: $x.base.price_usd,
                price_unit: $x.base.price_unit,
                price_unit_bytes: $x.base.price_unit_bytes,
                notes: $x.base.notes
              }
            }
          else empty end
      );

  ($r.data_size // 0) as $dataset_bytes |
  ($p.provider // "gcp") as $provider |
  ($p.currency // "USD") as $currency |
  ($p.sources // []) as $sources |

  ($p.regions[$region] // {}) as $region_prices |
  ($region_prices.pricing_compute // {}) as $pc |
  ($pc.capacity // {}) as $capacity_root |
  ($pc.on_demand // {}) as $od |
  ($od.monthly // null) as $on_demand |

  # Expand capacity variants and billing periods robustly
  ( [ obj_entries($capacity_root)[]
      | . as $variant
      | obj_entries($variant.value)[]
      | {variant: $variant.key, period: .key, node: .value}
    ] ) as $capacity_nodes |

  {
    system: $r.system,
    date: $r.date,
    machine: $r.machine,
    cluster_size: $r.cluster_size,
    proprietary: $r.proprietary,
    tuned: $r.tuned,
    comment: $r.comment,
    tags: $r.tags,
    load_time: $r.load_time,
    data_size: $r.data_size,
    result: $r.result,
    billed_slot_sec: $r.billed_slot_sec,
    billed_bytes: $r.billed_bytes,
    costs:
      (
        # Capacity: one entry per (variant x period x tier)
        ( $capacity_nodes
          | map(
              . as $cp
              | ( ($cp.node.tiers // []) | (if (.|type)=="array" then . else [] end) )
              | map(
                  . as $t
                  | select( ($t.price_usd? // null) != null and ($t.price_unit_seconds? // null) != null )
                  | {
                      tier: $t.name,
                      provider: $provider,
                      region: $region,
                      compute_model: "capacity",
                      pricing_variant: $cp.variant,
                      billing_period: $cp.period,
                      compute_costs: map2d($r.billed_slot_sec; ($t.price_usd / $t.price_unit_seconds)),
                      pricing_base: {
                        price_usd: $t.price_usd,
                        price_unit: $t.price_unit,
                        price_unit_seconds: $t.price_unit_seconds,
                        currency: $currency,
                        notes: $t.notes
                      },
                      assumptions: {
                        dataset_bytes: $dataset_bytes,
                        metrics: ["billed_slot_sec"]
                      },
                      sources: $sources,
                      storage_costs: storage_costs($p; $region; $dataset_bytes)
                    }
                )
            )
          | add
        ) +

        # On-demand
        ( if ($on_demand|type)=="object" and ($on_demand.price_unit_bytes? // 0) != 0 then
            [
              {
                tier: "OnDemand",
                provider: $provider,
                region: $region,
                compute_model: "on_demand",
                billing_period: "monthly",
                compute_costs: map2d($r.billed_bytes; ($on_demand.price_usd / $on_demand.price_unit_bytes)),
                pricing_base: {
                  price_usd: $on_demand.price_usd,
                  price_unit: $on_demand.price_unit,
                  price_unit_bytes: $on_demand.price_unit_bytes,
                  currency: $currency,
                  notes: $on_demand.notes
                },
                assumptions: {
                  dataset_bytes: $dataset_bytes,
                  metrics: ["billed_bytes"]
                },
                sources: $sources,
                storage_costs: storage_costs($p; $region; $dataset_bytes)
              }
            ]
          else [] end )
      )
  }
'