"""Export Agents SDK spans to the table in schema.sql."""
import base64
import json
import os
import re
from urllib.request import Request, urlopen
from urllib.parse import urlencode

from agents.tracing.processors import TracingExporter

class ClickHouseExporter(TracingExporter):
    def __init__(self):
        self.url = os.getenv("CH_URL", "http://localhost:8123")
        self.database = os.getenv("CH_DB", "default")
        self.table = os.getenv("CH_SPAN_TABLE", "agent_spans_raw")
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", self.table):
            raise ValueError("CH_SPAN_TABLE must be an SQL identifier")
        self.error = None

    def export(self, items):
        rows = []
        for item in items:
            data = item.export()
            if not data or data.get("object") != "trace.span":
                continue
            span = data.get("span_data") or {}
            response = getattr(getattr(item, "span_data", None), "response", None)
            rows.append({
                "trace_id": data["trace_id"],
                "span_id": data["id"],
                "parent_id": data.get("parent_id") or "",
                "started_at": data["started_at"],
                "ended_at": data["ended_at"],
                "span_type": span.get("type", ""),
                "span_name": span.get("name") or span.get("type", ""),
                "model": getattr(response, "model", None) or span.get("model") or "",
                "error": json.dumps(data["error"]) if data.get("error") else "",
                "span_data": json.dumps(span, default=str),
            })
        if not rows:
            return
        query = urlencode({"database": self.database, "date_time_input_format": "best_effort",
                           "query": f"INSERT INTO {self.table} FORMAT JSONEachRow"})
        credentials = f'{os.getenv("CH_USER", "default")}:{os.getenv("CH_PASS", "")}'
        request = Request(self.url.rstrip("/") + "/?" + query,
                          data=("\n".join(json.dumps(row) for row in rows) + "\n").encode(),
                          headers={"Authorization": "Basic " + base64.b64encode(credentials.encode()).decode(),
                                   "Content-Type": "application/x-ndjson"})
        try:
            with urlopen(request, timeout=10) as response:
                response.read()
        except Exception as exc:
            self.error = exc
            raise

    def raise_if_failed(self):
        """BatchTraceProcessor logs background errors; make CLI failure observable too."""
        if self.error is not None:
            raise RuntimeError("ClickHouse trace export failed") from self.error
