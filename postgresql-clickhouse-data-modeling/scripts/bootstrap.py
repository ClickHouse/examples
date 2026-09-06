"""Local PeerDB API bootstrap; standard library only, runs in a container."""
import json
import os
import time
import urllib.error
import urllib.request

BASE = os.environ.get("PEERDB_API", "http://flow-api:8113")


def request(path, payload=None):
    body = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(BASE + path, data=body, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            return json.load(response)
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f"PeerDB {path}: HTTP {exc.code}: {exc.read().decode()}") from exc


# A running container is insufficient: wait for the actual version API.
for attempt in range(30):
    try:
        version = request("/v1/version")
        print("PeerDB:", version, flush=True)
        break
    except (OSError, ValueError, RuntimeError) as exc:
        if attempt == 29:
            raise RuntimeError("PeerDB API did not become ready") from exc
        time.sleep(2)

peers = [
    {"name": "postgres", "type": 3, "postgres_config": {
        "host": "postgres", "port": 5432, "user": "admin", "password": "password",
        "database": "clickhouse_pg_db", "disable_tls": True}},
    {"name": "clickhouse", "type": 8, "clickhouse_config": {
        "host": "clickhouse", "port": 9000, "user": "demo", "password": "local-example-password",
        "database": "stackoverflow", "disable_tls": True}},
]
for peer in peers:
    result = request("/v1/peers/create", {"peer": peer, "allow_update": False})
    # PeerDB can return HTTP 200 with a FAILED response: check the JSON too.
    if result.get("status") != "CREATED":
        raise RuntimeError(f"Peer {peer['name']} was not created: {result}")
    print("Created peer:", peer["name"], flush=True)

config = {
    "flow_job_name": "stackoverflow_demo",
    "source_name": "postgres",
    "destination_name": "clickhouse",
    "table_mappings": [{"source_table_identifier": "public." + table,
                        "destination_table_identifier": table}
                       for table in ("users", "posts", "votes", "comments")],
    "idle_timeout_seconds": 5,
    "do_initial_snapshot": True,
    "snapshot_num_rows_per_partition": 1000,
    "snapshot_max_parallel_workers": 1,
    "snapshot_num_tables_in_parallel": 1,
    "soft_delete_col_name": "_peerdb_is_deleted",
    "synced_at_col_name": "_peerdb_synced_at",
}
result = request("/v1/flows/cdc/create", {"connection_configs": config})
workflow = result.get("workflowId") or result.get("workflow_id")
if not workflow:
    raise RuntimeError(f"Mirror was not created: {result}")
print("Created mirror workflow:", workflow, flush=True)
