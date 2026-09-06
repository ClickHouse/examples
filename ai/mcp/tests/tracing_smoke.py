"""Exercise the actual Agents SDK exporter and ClickHouse schema without an LLM."""
from datetime import datetime
import json
import os
from pathlib import Path
import sys
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import urlopen
from uuid import uuid4

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "openai-agents"))
from agents import custom_span, trace
from agents.tracing import set_trace_processors
from clickhouse_processor import ClickHouseExporter

def query(sql, database="default"):
    url = os.getenv("CH_URL", "http://localhost:8123")
    with urlopen(url + "/?" + urlencode({"database": database, "query": sql}), data=b"", timeout=10) as response:
        return response.read().decode()

def main():
    database = "mcp_trace_test_" + uuid4().hex
    query(f"CREATE DATABASE {database}")
    os.environ["CH_DB"] = database
    try:
        for sql in (ROOT / "openai-agents/schema.sql").read_text().split(";"):
            if sql.strip():
                query(sql, database)
        set_trace_processors([])
        spans = []
        with trace("exporter-smoke"):
            for name in ["success", "failure"]:
                with custom_span(name) as span:
                    if name == "failure":
                        span.set_error({"message": "fixture failure", "data": {}})
                spans.append(span)
        exporter = ClickHouseExporter()
        exporter.export(spans)
        rows = [json.loads(row) for row in query(
            "SELECT SpanName, Duration, StatusCode, StatusMessage FROM agent_spans ORDER BY SpanName FORMAT JSONEachRow",
            database).splitlines()]
        assert len(rows) == 2, rows
        assert rows[0]["StatusCode"] == "Error" and "fixture failure" in rows[0]["StatusMessage"]
        assert rows[1]["StatusCode"] == "Ok" and not rows[1]["StatusMessage"]
        data = spans[0].export()
        delta = datetime.fromisoformat(data["ended_at"]) - datetime.fromisoformat(data["started_at"])
        assert int(rows[1]["Duration"]) == (delta.seconds * 1_000_000 + delta.microseconds) * 1000
        class MalformedSpan:
            def export(self):
                return {**data, "started_at": "not-a-timestamp"}
        try:
            exporter.export([MalformedSpan()])
        except HTTPError:
            pass
        else:
            raise AssertionError("Malformed span was accepted")
        try:
            exporter.raise_if_failed()
        except RuntimeError:
            pass
        else:
            raise AssertionError("Background exporter failure was hidden")
        print("Passed: SDK success/error spans, nanosecond duration, and rejected insert propagation")
    finally:
        query(f"DROP DATABASE {database}")

if __name__ == "__main__":
    main()
