
# 1) pick a unique id (lowercase, no spaces)
JOB_ID="job_$(uuidgen | tr 'A-Z' 'a-z' | tr -d '-')"

# 2) run the query with that id (suppress row output)
bq query \
  --nouse_legacy_sql \
  --use_cache=false \
  --format=none \
  --quiet \
  --job_id="$JOB_ID" \
  "SELECT ClientIP, ClientIP - 1, ClientIP - 2, ClientIP - 3, COUNT(*) AS c FROM test.hits GROUP BY ClientIP, ClientIP - 1, ClientIP - 2, ClientIP - 3 ORDER BY c DESC LIMIT 10;"

# 3) fetch metrics for exactly that job
bq show -j --format=json "$JOB_ID" | jq -r '{
  jobId: .jobReference.jobId,
  runtime_sec: ((.statistics.finalExecutionDurationMs|tonumber) / 1000),
  billed_slot_sec: ((.statistics.totalSlotMs|tonumber) / 1000),
  billed_bytes: ( (.statistics.query.totalBytesBilled // .statistics.totalBytesBilled // 0) | tonumber )
}'





