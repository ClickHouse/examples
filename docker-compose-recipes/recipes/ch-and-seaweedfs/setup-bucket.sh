#!/bin/sh
set -eu
# The only retries are bounded startup retries; a failed setup exits nonzero.
s3() {
  aws --endpoint-url "$S3_ENDPOINT" --cli-connect-timeout 2 --cli-read-timeout 5 s3api "$@"
}
attempt=0
while [ "$attempt" -lt 30 ]; do
  attempt=$((attempt + 1))
  if s3 head-bucket --bucket clickhouse; then
    echo 'Bucket clickhouse is ready'
    exit 0
  fi
  sleep 2
done
echo 'S3 bucket setup failed after 30 attempts' >&2
exit 1
