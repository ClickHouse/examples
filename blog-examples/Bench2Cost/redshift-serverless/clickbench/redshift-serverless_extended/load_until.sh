#!/usr/bin/env bash
set -euo pipefail
#
# Usage:
#   ./load_until.sh <schema.table> [csv_file] [target_rows]
#
# Example:
#   ./load_until.sh public.hits hits.csv 1000000000
#
# Defaults:
#   csv_file: hits.csv.gz
#   target_rows: 1000000000
#
# Required env:
#   REDSHIFT_WORKGROUP, REDSHIFT_DATABASE, REDSHIFT_SECRET_ARN, REDSHIFT_IAM_ROLE_ARN,
#   S3_BUCKET  (S3_PREFIX optional)
# Optional env:
#   CSV_HAS_HEADER=1  (treat first row as header)
#   S3_PREFIX=""      (optional S3 prefix)
#   REGION="us-west-2" (AWS region)

TABLE="${1:?Usage: $0 <schema.table> [csv_file] [target_rows] }"
CSV="${2:-hits.csv.gz}"
TARGET="${3:-1000000000}"

# -------- helpers ---------
need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' not found in PATH" >&2; exit 1; }; }
need aws; need jq

# CSV is now set from command line args
: "${REDSHIFT_WORKGROUP:?Set REDSHIFT_WORKGROUP}"
: "${REDSHIFT_DATABASE:?Set REDSHIFT_DATABASE}"
: "${REDSHIFT_IAM_ROLE_ARN:?Set REDSHIFT_IAM_ROLE_ARN}"
: "${S3_BUCKET:?Set S3_BUCKET}"

S3_PREFIX="${S3_PREFIX:-}"
CSV_HAS_HEADER="${CSV_HAS_HEADER:-0}"

SCHEMA="${TABLE%%.*}"
NAME="${TABLE#*.}"

S3_KEY="${S3_PREFIX%/}/$(basename "$CSV")"
S3_URI="s3://$S3_BUCKET/${S3_KEY#./}"

aws_redshift_sql_json() {
  # Execute SQL and print the final JSON result.
  # Usage: aws_redshift_sql_json "SELECT 1"
  local sql="$1"
  local id status
  id="$(aws redshift-data execute-statement \
        --workgroup-name "$REDSHIFT_WORKGROUP" \
        --database "$REDSHIFT_DATABASE" \
        --region us-east-2 \
        --sql "$sql" \
        --query 'Id' \
        --output text)"
  # Poll status
  while :; do
    status="$(aws redshift-data describe-statement --region us-east-2 --id "$id" --query 'Status' --output text)"
    case "$status" in
      FINISHED) break ;;
      FAILED|ABORTED)
        echo "SQL failed: $sql" >&2
        aws redshift-data describe-statement --region us-east-2 --id "$id" >&2
        exit 1
        ;;
      *) sleep 1 ;;
    esac
  done
  # Return results if any (COPY has no result set; this will be empty which is fine)
  aws redshift-data get-statement-result --region us-east-2 --id "$id" 2>/dev/null || true
}

aws_redshift_sql_value() {
  # Execute SQL and print first cell as a scalar (string/number)
  # Returns empty on no records.
  local json
  json="$(aws_redshift_sql_json "$1")" || return 1
  if [[ -z "$json" || "$json" == "null" ]]; then
    echo ""
    return 0
  fi
  # try longValue then stringValue
  jq -r 'if (.Records|length)==0 then "" else
           (.Records[0][0].longValue // .Records[0][0].stringValue // "")
         end' <<<"$json"
}

table_exists() {
  local sql="SELECT 1
             FROM information_schema.tables
             WHERE table_schema = '$SCHEMA' AND table_name = '$NAME'
             LIMIT 1"
  [[ -n "$(aws_redshift_sql_value "$sql")" ]]
}

row_count() {
  # Returns current number of rows (0 if table does not exist)
  if ! table_exists; then
    echo 0
    return
  fi
  local sql="SELECT COUNT(*) FROM \"$SCHEMA\".\"$NAME\""
  local val
  val="$(aws_redshift_sql_value "$sql")"
  echo "${val:-0}"
}

run_copy() {
  # Extract schema and table name
  IFS='.' read -r SCHEMA NAME <<< "$TABLE"
  
  # Set S3 URI
  local s3_path="${S3_PREFIX}${S3_PREFIX:+/}${CSV}"
  local s3_uri="s3://${S3_BUCKET}/${s3_path}"
  
  local header=""
  if [[ "${CSV_HAS_HEADER:-0}" == "1" ]]; then
    header="IGNOREHEADER 1"
  fi

  # Note: Adjust COPY options if your CSV differs (delimiter, quotes, etc.).
  local copy_sql
  copy_sql=$(cat <<SQL
COPY ${TABLE}
FROM 's3://clickhouse-public-datasets/hits_compatible/hits.csv.gz'
IAM_ROLE 'arn:aws:iam::244449518788:role/service-role/AmazonRedshift-CommandsAccessRole-20250904T163510'
CSV
GZIP
DELIMITER ','
QUOTE '"'
IGNOREHEADER 1
REGION 'eu-central-1';
SQL
)

  echo "Executing COPY command for $s3_uri"
  # Execute COPY
  if ! aws_redshift_sql_json "$copy_sql" >/dev/null; then
    echo "Error executing COPY command"
    return 1
  fi
  
  # Verify the row count after COPY
  echo "Verifying row count after COPY..."
  local count_sql="SELECT COUNT(*) FROM ${TABLE};"
  local row_count
  
  # Try multiple times to get row count in case of connection issues
  local max_retries=3
  local retry_delay=2
  local retry_count=0
  
  while [ $retry_count -lt $max_retries ]; do
    if row_count=$(aws_redshift_sql_value "$count_sql" 2>/dev/null); then
      echo "Current row count in hits_1b: $row_count"
      
      # If we got a valid count, update the current row count
      if [[ $row_count =~ ^[0-9]+$ ]]; then
        current=$row_count
        break
      fi
    fi
    
    retry_count=$((retry_count + 1))
    if [ $retry_count -lt $max_retries ]; then
      echo "Retrying row count query ($retry_count/$max_retries)..."
      sleep $retry_delay
    else
      echo "Warning: Failed to verify row count after $max_retries attempts"
      return 1
    fi
  done
}
# --------------------------

echo "Checking current row count for $TABLE ..."
current=$(row_count 2>/dev/null || echo 0)
echo "Rows before loading: $current"

if (( current >= TARGET )); then
  echo "Table already has $current rows (target: $TARGET). Nothing to do."
  exit 0
fi

iter=0
while (( current < TARGET )); do
  iter=$((iter+1))
  echo "Iteration #$iter: loading $CSV into $TABLE"
  
  # Store the start time
  start_time=$(date +%s)
  
  # Run the copy command
  if ! run_copy; then
    echo "Error in run_copy. Retrying in 5 seconds..."
    sleep 5
    continue
  fi
  
  # Get the new row count
  new_count=$(row_count 2>/dev/null || echo $current)
  
  # Calculate rows loaded in this iteration
  rows_loaded=$((new_count - current))
  
  # Calculate time taken
  end_time=$(date +%s)
  time_taken=$((end_time - start_time))
  
  # Calculate rows per second
  if (( time_taken > 0 )); then
    rows_per_sec=$((rows_loaded / time_taken))
  else
    rows_per_sec=0
  fi
  
  # Update current count
  current=$new_count
  
  # Print stats
  printf '  Rows loaded: %d | Total: %d | Rows/s: %d | Time: %d seconds\n' \
    "$rows_loaded" "$current" "$rows_per_sec" "$time_taken"
  
  # If no rows were loaded, we should probably stop to avoid infinite loop
  if (( rows_loaded == 0 )); then
    echo "No new rows were loaded. Stopping to prevent infinite loop."
    break
  fi
  
  # Small delay to avoid overwhelming the database
  sleep 2
done

echo "Load process completed. Final row count: $current"
if (( current >= TARGET )); then
  echo "Successfully reached target of $TARGET rows!"
else
  echo "Warning: Stopped at $current rows, which is below the target of $TARGET."
  exit 1
fi
