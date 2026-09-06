#!/usr/bin/env bash
# Shared connection setup and the SLA snapshot used by watch/investigate.
# shellcheck shell=bash
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

positive_integer() {
  if [[ ! "$2" =~ ^[1-9][0-9]{0,8}$ ]]; then
    printf '%s must be a positive integer (at most 9 digits).\n' "$1" >&2
    return 1
  fi
}

native_connection() {
  : "${CH_HOST:?source config.env first}" "${CH_PASSWORD:?source config.env first}"
  positive_integer CH_PORT "${CH_PORT:-9440}"
  # Used by the scripts sourcing this file.
  # shellcheck disable=SC2034
  NATIVE_ARGS=(--host "$CH_HOST" --port "${CH_PORT:-9440}" --secure --user "${CH_USER:-default}")
  export CLICKHOUSE_PASSWORD="$CH_PASSWORD"
}

sla_config() {
  : "${SERVICE_ID:?source config.env first}"
  if [[ ! "$SERVICE_ID" =~ ^[a-zA-Z0-9-]+$ ]]; then
    echo 'SERVICE_ID must contain only letters, digits and hyphens.' >&2
    return 1
  fi
  SLA_MS=${SLA_MS:-200}
  MIN_SAMPLES=${MIN_SAMPLES:-100}
  positive_integer SLA_MS "$SLA_MS"
  positive_integer MIN_SAMPLES "$MIN_SAMPLES"
}

sla_snapshot() {
  local snapshot
  if ! snapshot=$(clickhousectl cloud service query --id "$SERVICE_ID" \
      --no-auto-enable --format TSV --queries-file "$SCRIPT_DIR/sla.sql"); then
    echo 'SLA query failed; latency is unknown.' >&2
    return 1
  fi
  # Require exactly one TSV row; never interpret an API error or an empty
  # response as a healthy window. quantileExactIf returns integer milliseconds.
  if [[ ! "$snapshot" =~ ^([0-9]+)$'\t'([0-9]+)$'\t'([0-9]+)$ ]]; then
    echo 'Unexpected SLA response; expected successes, failures and p99 as TSV.' >&2
    return 1
  fi
  SAMPLES=${BASH_REMATCH[1]}
  FAILURES=${BASH_REMATCH[2]}
  P99_MS=${BASH_REMATCH[3]}
  if (( SAMPLES == 0 )); then
    SLA_STATUS=NO_DATA
    P99_MS=n/a
  elif (( SAMPLES < MIN_SAMPLES )); then
    SLA_STATUS=INSUFFICIENT_SAMPLES
  elif (( P99_MS > SLA_MS )); then
    SLA_STATUS=BREACH
  else
    SLA_STATUS=OK
  fi
}

print_snapshot() {
  printf '[%s] %s p99=%sms (target=%sms, completed=%s, failed=%s, window=60s)\n' \
    "$(date +%T)" "$SLA_STATUS" "$P99_MS" "$SLA_MS" "$SAMPLES" "$FAILURES"
  if (( FAILURES > 0 )); then
    echo '  Query failures are excluded from p99; investigate them even if latency is OK.'
  fi
}
