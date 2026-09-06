"""Manual Grafana recipe check, using only the Python standard library."""
import base64
import json
import time
import urllib.error
import urllib.request

BASE = "http://grafana:3000"
AUTH = "Basic " + base64.b64encode(b"admin:local-grafana-password").decode()


def api(path, payload=None):
    body = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(BASE + path, data=body,
        headers={"Authorization": AUTH, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            return json.load(response)
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f"Grafana {path}: HTTP {exc.code}: {exc.read().decode()}") from exc


# Plugin installation/provisioning can take longer than HTTP server startup.
deadline = time.monotonic() + 180
while True:
    try:
        health = api("/api/health")
        datasource = api("/api/datasources/uid/clickhouse")
        dashboard = api("/api/dashboards/uid/clickhouse-example")["dashboard"]
        plugin = api("/api/plugins/grafana-clickhouse-datasource/settings")
        if health.get("database") != "ok":
            raise RuntimeError(f"Grafana database is not healthy: {health}")
        break
    except (OSError, ValueError, KeyError, RuntimeError) as exc:
        if time.monotonic() >= deadline:
            raise RuntimeError("Grafana provisioning was not ready within 180 seconds") from exc
        time.sleep(2)

assert datasource["type"] == "grafana-clickhouse-datasource", datasource
assert datasource["jsonData"]["username"] == "grafana_reader", datasource
assert health["version"] == "13.2.1", health
assert plugin["info"]["version"] == "4.21.2", plugin
panel = dashboard["panels"][0]
assert panel["title"] == "Order total", panel
# Execute the actual provisioned target through Grafana's datasource API.
query = dict(panel["targets"][0], intervalMs=1000, maxDataPoints=100)
now = int(time.time() * 1000)
result = api("/api/ds/query", {"queries": [query], "from": str(now - 3600000), "to": str(now)})
response = result["results"]["A"]
assert not response.get("error"), response
frames = response["frames"]
assert len(frames) == 1, frames
assert frames[0]["data"]["values"] == [[45]], frames
print("Grafana:", health["version"], "; ClickHouse plugin:", plugin["info"]["version"])
print("OK: datasource and dashboard provisioned; Order total panel query returned 45")
