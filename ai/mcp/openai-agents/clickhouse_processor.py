from agents.tracing.processors import TracingExporter
import requests
import json
import os


class ClickHouseExporter(TracingExporter):    
    def __init__(self):
        self._ch_url = os.getenv("CH_URL", "http://localhost:8123")
        self._ch_db = os.getenv("CH_DB", "default")
        self._span_tbl = os.getenv("CH_SPAN_TABLE", "agent_spans_raw")
        self._auth = None
        if os.getenv("CH_USER") or os.getenv("CH_PASS"):
            self._auth = (os.getenv("CH_USER", "default"), os.getenv("CH_PASS", ""))
    
    def export(self, items: list) -> None:
        print(f"[ClickHouseExporter] Exporting {len(items)} items")
        
        spans = []
        for item in items:
            if "Span" in type(item).__name__:                
                span_data = {}
                if hasattr(item, "span_data") and item.span_data:
                    if hasattr(item.span_data, "export"):
                        span_data = item.span_data.export()
                    
                    # Extract model - not included in export() by default
                    if hasattr(item.span_data, "response") and item.span_data.response:
                        if hasattr(item.span_data.response, "model"):
                            span_data["model"] = str(item.span_data.response.model)
                                
                span_export = {**item.export(), "span_data": span_data,}
                
                spans.append(span_export)
                print(f"[ClickHouseExporter] Added span: {item.span_id} type={span_data.get('type')}")
        
        print(f"[ClickHouseExporter] Prepared {len(spans)} spans")
        
        try:
            if spans:
                body = "\n".join(json.dumps(s, ensure_ascii=False) for s in spans) + "\n"
                print(f"[ClickHouseExporter] Inserting {len(spans)} spans into {self._span_tbl}")
                resp = requests.post(
                    f"{self._ch_url}/?database={self._ch_db}",
                    params={"query": f"INSERT INTO {self._span_tbl} FORMAT JSONEachRow"},
                    data=body.encode("utf-8"),
                    auth=self._auth,
                    timeout=5,
                )
                print(f"[ClickHouseExporter] Spans response: {resp.status_code} - {resp.text}")
        except Exception as e:
            print(f"[ClickHouseExporter] Error: {e}")
            import traceback
            traceback.print_exc()