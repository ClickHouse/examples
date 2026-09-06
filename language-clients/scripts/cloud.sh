#!/usr/bin/env bash
# Provision the ClickHouse Cloud service for the language client tour.
# All administration goes through clickhousectl; no Cloud API secrets are copied.
#
#   scripts/cloud.sh create   create a small, IP-restricted service (incurs Cloud charges)
#   scripts/cloud.sh setup    wait for running, create database + app user, write .env
#   scripts/cloud.sh stop     stop compute (storage charges may continue)
#   scripts/cloud.sh recover <service-id>   adopt a service if create timed out
#
# Requires: clickhousectl (API-key login, Admin role), jq, curl, openssl.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
state_file="$root/.cloud-service.json"
intent_file="$root/.cloud-create-intent.json"
response_file="$root/.cloud-create-response.json"
env_file="$root/.env"

name="${CLIENT_TOUR_SERVICE_NAME:-language-clients-example}"
provider="${CLIENT_TOUR_PROVIDER:-aws}"
region="${CLIENT_TOUR_REGION:-eu-west-1}"
org_args=()
if [[ -n "${CLIENT_TOUR_ORG_ID:-}" ]]; then org_args=(--org-id "$CLIENT_TOUR_ORG_ID"); fi

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required tool: $1" >&2; exit 1; }; }
need clickhousectl; need jq; need openssl

cli() { clickhousectl cloud service "$@" ${org_args[@]+"${org_args[@]}"}; }

# One statement per call; the Query API rejects ';'-separated scripts.
query() { local id="$1"; shift; printf '%s' "$1" | cli query --id "$id" --queries-file - --json >/dev/null; }

service_id() { jq -r .id "$state_file"; }

wait_running() {
  local id="$1" deadline=$(( $(date +%s) + 600 )) state
  while (( $(date +%s) < deadline )); do
    state="$(cli get "$id" --json | jq -r .state)"
    echo "Service $id: $state" >&2
    case "$state" in
      running) return 0 ;;
      failed|deleted|terminated) echo "Service is $state; inspect it before retrying." >&2; exit 1 ;;
      stopped) echo "Service is stopped; run: clickhousectl cloud service start $id" >&2; exit 1 ;;
    esac
    sleep 10
  done
  echo "Service did not become running within ten minutes. State file retained." >&2; exit 1
}

case "${1:-}" in
  create)
    if [[ -e "$state_file" || -e "$intent_file" || -e "$response_file" ]]; then
      echo "A service creation was already attempted. Run 'setup' if .cloud-service.json exists." >&2
      echo "Otherwise inspect 'clickhousectl cloud service list' and use 'recover <service-id>'." >&2
      exit 1
    fi
    need curl
    ip="${CLIENT_TOUR_IP:-$(curl -4fsS https://api.ipify.org)}"
    [[ "$ip" == *:* ]] && cidr="$ip/128" || cidr="$ip/32"
    echo "Creating $provider $region service '$name': one 8 GiB replica, idle scaling on, 5 minute idle timeout."
    echo "Only $cidr may connect. This incurs Cloud charges; this script never deletes the service."
    # Record intent first: a timeout is ambiguous and the API may still have created the service.
    jq -n --arg name "$name" --arg provider "$provider" --arg region "$region" \
      '{name:$name, provider:$provider, region:$region, attemptedAt:(now|todate)}' > "$intent_file"
    chmod 600 "$intent_file"
    cli create --name "$name" --provider "$provider" --region "$region" \
      --min-replica-memory-gb 8 --max-replica-memory-gb 8 --num-replicas 1 \
      --idle-scaling true --idle-timeout-minutes 5 \
      --ip-allow "$cidr=language-clients-example" --tag example=language-clients --json > "$response_file"
    chmod 600 "$response_file"   # contains the one-time default-user password
    id="$(jq -r '.service.id // empty' "$response_file")"
    [[ -n "$id" ]] || { echo "Create response has no service ID; response retained in $response_file" >&2; exit 1; }
    jq -n --arg id "$id" --arg name "$name" --arg provider "$provider" --arg region "$region" \
      '{id:$id, name:$name, provider:$provider, region:$region, memoryGiB:8, replicas:1}' > "$state_file"
    echo "Created service $id. Next: scripts/cloud.sh setup"
    ;;

  recover)
    [[ -e "$state_file" ]] && { echo "Service ID already saved; run setup." >&2; exit 1; }
    id="${2:-}"
    [[ "$id" =~ ^[a-f0-9-]{36}$ ]] || { echo "Usage: scripts/cloud.sh recover <service-id>" >&2; exit 1; }
    svc="$(cli get "$id" --json)"
    if [[ "$(jq -r .name <<<"$svc")" != "$(jq -r .name "$intent_file")" ]]; then
      echo "Service name does not match the saved creation intent; refusing." >&2; exit 1
    fi
    jq --arg id "$id" '. + {id:$id}' "$intent_file" > "$state_file"
    echo "Recovered $id; run setup."
    ;;

  setup)
    id="$(service_id)"
    wait_running "$id"
    svc="$(cli get "$id" --json)"
    host="$(jq -r '.endpoints[] | select(.protocol=="https") | .host' <<<"$svc")"
    https_port="$(jq -r '.endpoints[] | select(.protocol=="https") | .port' <<<"$svc")"
    native_port="$(jq -r '.endpoints[] | select(.protocol=="nativesecure") | .port' <<<"$svc")"
    [[ -n "$host" && -n "$https_port" && -n "$native_port" ]] || { echo "Service endpoints missing from response." >&2; exit 1; }

    query "$id" "$(cat "$root/sql/01-database.sql")"
    echo "Created database client_tour"

    if [[ -e "$env_file" ]]; then
      password="$(sed -n 's/^CLICKHOUSE_PASSWORD=//p' "$env_file")"
      [[ -n "$password" ]] || { echo "Existing .env has no CLICKHOUSE_PASSWORD; refusing to overwrite it." >&2; exit 1; }
    else
      # Cloud requires upper, lower, digit and a special character; hex keeps the rest shell-safe.
      password="Aa1!$(openssl rand -hex 24)"
      umask 077
      cat > "$env_file" <<ENV
CLICKHOUSE_HOST=$host
CLICKHOUSE_HTTPS_PORT=$https_port
CLICKHOUSE_NATIVE_PORT=$native_port
CLICKHOUSE_USER=client_tour_app
CLICKHOUSE_PASSWORD=$password
CLICKHOUSE_DATABASE=client_tour
ENV
    fi
    # .env is written BEFORE the CREATE USER request so setup is resumable.
    query "$id" "CREATE USER IF NOT EXISTS client_tour_app IDENTIFIED BY '$password'"
    # Each implementation creates and drops its own table, so it needs DDL rights on this database only.
    query "$id" "GRANT SELECT, INSERT, CREATE TABLE, DROP TABLE ON client_tour.* TO client_tour_app"
    echo "Created application user client_tour_app with SELECT, INSERT, CREATE TABLE, DROP TABLE on client_tour.*"
    echo "Credentials written to $env_file (gitignored, mode 0600)."
    echo "Grants:"
    cli query --id "$id" --query "SHOW GRANTS FOR client_tour_app"
    ;;

  stop)
    id="$(service_id)"
    cli stop "$id" --json | jq -r '"Stop accepted for \(.id // "'"$id"'"): \(.state)"'
    echo "Service retained; storage charges may continue. Delete it in the Cloud console or with 'clickhousectl cloud service delete $id' when finished."
    ;;

  *)
    echo "Usage: scripts/cloud.sh create|setup|stop|recover <service-id>" >&2; exit 1 ;;
esac
