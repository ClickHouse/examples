#!/bin/bash

# ClickBench Results Cost Enrichment Script (Shell Version)
# This script matches local pricing files with benchmark result files from ClickHouse/ClickBench
# and enriches the results with cost calculations.

set -e

# Configuration
CLICKBENCH_REPO="https://raw.githubusercontent.com/ClickHouse/ClickBench/main"
FOLDER_NAME="clickhouse-cloud"
PRICING_DIR="pricings"
OUTPUT_DIR="results"
TEMP_DIR="/tmp/benchmark_tmp"

# Create necessary directories
mkdir -p "$OUTPUT_DIR"
mkdir -p "$TEMP_DIR"

echo "Starting benchmark results enrichment process..."

# Process each pricing file
for pricing_file in "$PRICING_DIR"/*.json; do
    [ -f "$pricing_file" ] || continue

    echo "Processing pricing file: $pricing_file"
    filename=$(basename "$pricing_file")

    # Construct result file URL
    result_path="${FOLDER_NAME}/results/$filename"
    result_url="${CLICKBENCH_REPO}/${result_path}"
    output_file="${OUTPUT_DIR}/${filename}"

    echo "  Fetching result file: $result_url"

    # Download result file
    if ! curl -sSf "$result_url" -o "${TEMP_DIR}/result.json" 2>/dev/null; then
        echo "  Error: Could not fetch result file $result_url"
        continue
    fi

    provider=$(jq -r '.provider' "$pricing_file")
    region=$(jq -r '.region' "$pricing_file")

    # Process each tier
    tier_count=$(jq '.tier | length' "$pricing_file")

    for ((i=0; i<tier_count; i++)); do
        # Extract tier data
        tier_name=$(jq -r ".tier[$i].name" "$pricing_file")
        compute_cost=$(jq -r ".tier[$i].compute" "$pricing_file")
        storage_cost=$(jq -r ".tier[$i].storage" "$pricing_file")
        storage_price_unit=$(jq -r ".tier[$i].storage_price_unit" "$pricing_file")
        memory_size=$(jq -r ".memory_size" "$pricing_file")
        compute_price_unit=$(jq -r ".tier[$i].compute_price_unit" "$pricing_file")
        cluster_size=$(jq -r ".cluster_size" "$pricing_file")

        echo "Processing tier: $tier_name"

        # For the first tier, start with a clean result file
        if [[ $i -eq 0 ]]; then
            cp "${TEMP_DIR}/result.json" "${TEMP_DIR}/base.json"
        fi

        # Process the current tier's costs and include pricing info
        pricing_content=$(cat "$pricing_file")
        jq --arg tier_name "$tier_name" \
           --arg compute_cost "$compute_cost" \
           --arg storage_cost "$storage_cost" \
           --arg storage_price_unit "$storage_price_unit" \
           --arg memory_size "$memory_size" \
           --arg compute_price_unit "$compute_price_unit" \
           --arg cluster_size "$cluster_size" \
           --arg provider "$provider" \
           --arg region "$region" \
           --arg pricing_json "$pricing_content" '
        # Parse pricing JSON
        ($pricing_json | fromjson) as $pricing_data |

        # Bind dataset size early so we never depend on "." later
        (.data_size | tonumber) as $bytes |

        # Calculate compute cost for each run of each query
        [ .result[] |
            [ .[] |
                (. * (($compute_cost | tonumber) / 3600) *
                (($memory_size | tonumber) / ($compute_price_unit | tonumber)) *
                ($cluster_size | tonumber))
            ]
        ] as $compute_costs |

        # Calculate storage cost using bound $bytes
        ((($storage_cost | tonumber) * ($bytes / ($storage_price_unit | tonumber)))) as $storage_cost_value |

        # Find this tier in the pricing file
        $pricing_data.tier | map(select(.name == $tier_name))[0] as $tier_pricing |

        # Calculate price per byte
        (($tier_pricing.storage | tonumber) / ($tier_pricing.storage_price_unit | tonumber)) as $price_per_byte |

        # Create the cost entry for this tier with pricing info
        {
            tier: $tier_name,
            provider: $provider,
            region: $region,
            compute_costs: $compute_costs,
            storage_cost: $storage_cost_value,
            storage_costs: [
              {
                model: "object",
                term: "active",
                period: "monthly",
                price_per_byte: $price_per_byte,
                bytes: $bytes,
                estimated_cost: $storage_cost_value,
                pricing_base: {
                  price_usd: $tier_pricing.storage,
                  price_unit: "byte_month",
                  price_unit_bytes: $tier_pricing.storage_price_unit,
                  notes: "Object storage in ClickHouse Cloud (list price)."
                }
              }
            ],
            pricing_base: {
                compute: $tier_pricing.compute,
                compute_price_unit: $tier_pricing.compute_price_unit,
                storage: $tier_pricing.storage,
                storage_price_unit: $tier_pricing.storage_price_unit
            }
        }' "${TEMP_DIR}/result.json" > "${TEMP_DIR}/tier_${i}.json"

        # If this is the first tier, initialize the costs array
        if [[ $i -eq 0 ]]; then
            jq --slurpfile tier "${TEMP_DIR}/tier_0.json" '
            . + { costs: $tier }' "${TEMP_DIR}/base.json" > "${TEMP_DIR}/enriched.json"
        else
            # Append this tier's costs to the existing costs array
            jq --slurpfile tier "${TEMP_DIR}/tier_${i}.json" '
            .costs += $tier' "${TEMP_DIR}/enriched.json" > "${TEMP_DIR}/enriched_tmp.json"
            mv "${TEMP_DIR}/enriched_tmp.json" "${TEMP_DIR}/enriched.json"
        fi

        # Handle multiple tiers
        if [[ $i -eq 0 ]]; then
            cp "${TEMP_DIR}/enriched.json" "$output_file"
        else
            jq -s 'add' "$output_file" "${TEMP_DIR}/enriched.json" > "${TEMP_DIR}/combined.json"
            mv "${TEMP_DIR}/combined.json" "$output_file"
        fi
    done

    echo "  Saved enriched results to: $output_file"
done

# Cleanup
rm -rf "$TEMP_DIR"

echo -e "\nEnrichment process completed!"
echo "Enriched results are available in the '$OUTPUT_DIR' directory."