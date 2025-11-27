#!/bin/bash

# Input and output directories
CSV_FILE="$(dirname "$0")/pricing_metadata.csv"
OUTPUT_DIR="$(dirname "$0")/pricings"

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Function to get pricing data for a provider and region
get_pricing_data() {
    local provider=$1
    local region=$2
    
    # Use jq to format the JSON array properly
    jq -n --arg provider "$provider" --arg region "$region" --rawfile csv "$CSV_FILE" '
    reduce (
        $csv | split("\n")[] |
        select(. != "" and startswith("provider") | not) |
        split(",") |
        select(.[0] == $provider and .[1] == $region)
    ) as $row (
        [];
        . + [{
            name: $row[2],
            compute: ($row[3] | tonumber),
            compute_price_unit: ($row[4] | tonumber),
            storage: ($row[5] | tonumber),
            storage_price_unit: ($row[6] | tonumber)
        }]
    ) | .[] |
    "        { \"name\": \"\(.name)\", \"compute\": \(.compute), \"compute_price_unit\": \(.compute_price_unit), \"storage\": \(.storage), \"storage_price_unit\": \(.storage_price_unit) }"
    ' | paste -sd ",\n" -
}

# Function to generate JSON for a provider-region combination
generate_pricing_json() {
    local provider=$1
    local region=$2
    local memory=$3
    local replicas=$4
    local version=$5
    
    # Generate output filename in the format: provider.cluster_size.memory.json
    output_file="${OUTPUT_DIR}/${provider}.${replicas}.${memory}.json"
    
    # Get pricing data as a JSON array
    tiers_json=$(jq -n --arg provider "$provider" --arg region "$region" --rawfile csv "$CSV_FILE" '
    [
        $csv | split("\n")[] |
        select(. != "" and startswith("provider") | not) |
        split(",") |
        select(.[0] == $provider and .[1] == $region) |
        {
            name: .[2],
            compute: (.[3] | tonumber),
            compute_price_unit: (.[4] | tonumber),
            storage: (.[5] | tonumber),
            storage_price_unit: (.[6] | tonumber)
        }
    ]' 2>/dev/null)
    
    # Generate JSON with proper formatting
    jq -n --arg date "$(date +%Y-%m-%d)" --arg region "$region" \
       --arg provider "$provider" --argjson memory $memory \
       --argjson replicas $replicas --argjson tiers "$tiers_json" '
    {
        date: $date,
        region: $region,
        provider: $provider,
        memory_size: $memory,
        cluster_size: $replicas,
        tier: $tiers
    }' > "$output_file"
    
    echo "Generated pricing file: $output_file"
}

# Main script execution
PROVIDERS=("aws" "gcp" "azure")
VERSION="1.8"

# Process each provider
for PROVIDER in "${PROVIDERS[@]}"; do
    case $PROVIDER in
        aws)
            REGION='us-east-1'
            ;;
        gcp)
            REGION='us-east1'
            ;;
        azure)
            REGION='eastus2'
            ;;
    esac
    
    # Single replica configurations
    for REPLICAS in 1; do
        for MEMORY in 8 12; do
            generate_pricing_json "$PROVIDER" "$REGION" "$MEMORY" "$REPLICAS" "$VERSION"
        done
    done
    
    # Multi-replica configurations
    for REPLICAS in 2 3; do
        for MEMORY in 8 12 16 32 64 120 236; do
            generate_pricing_json "$PROVIDER" "$REGION" "$MEMORY" "$REPLICAS" "$VERSION"
        done
    done
done

echo "Pricing file generation complete."
