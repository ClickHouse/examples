# CREATE TABLE IF NOT EXISTS agent_spans (
#   trace_id       String,
#   span_id        String,
#   parent_id      String,
#   workflow_name  String,
#   span_type      String,            -- e.g., AgentSpanData / FunctionSpanData / GenerationSpanData
#   started_at     DateTime64(3, 'UTC'),
#   ended_at       DateTime64(3, 'UTC'),
#   duration_ms    UInt32,
#   model          LowCardinality(String)  ,
#   tool_name      LowCardinality(String)  ,
#   group_id       String                  ,
#   metadata       JSON,
#   span_data      JSON
# )
# ENGINE = MergeTree
# PARTITION BY toYYYYMM(started_at)
# ORDER BY (trace_id, span_id, started_at);

# -- (optional) one row per trace
# CREATE TABLE IF NOT EXISTS agent_traces (
#   trace_id      String,
#   workflow_name String,
#   group_id      String NULL,
#   started_at    DateTime64(3, 'UTC'),
#   ended_at      DateTime64(3, 'UTC'),
#   duration_ms   UInt32,
#   metadata      JSON
# )
# ENGINE = MergeTree
# PARTITION BY toYYYYMM(started_at)
# ORDER BY (trace_id, started_at);

# CREATE TABLE agent_spans
# (
#     `Timestamp` DateTime64(9) CODEC(Delta(8), ZSTD(1)),
#     `TraceId` String CODEC(ZSTD(1)),
#     `SpanId` String CODEC(ZSTD(1)),
#     `ParentSpanId` String CODEC(ZSTD(1)),
#     `TraceState` String CODEC(ZSTD(1)),
#     `SpanName` LowCardinality(String) CODEC(ZSTD(1)),
#     `SpanKind` LowCardinality(String) CODEC(ZSTD(1)),
#     `ServiceName` LowCardinality(String) CODEC(ZSTD(1)),
#     `ResourceAttributes` Map(LowCardinality(String), String) CODEC(ZSTD(1)),
#     `ScopeName` String CODEC(ZSTD(1)),
#     `ScopeVersion` String CODEC(ZSTD(1)),
#     `SpanAttributes` Map(LowCardinality(String), String) CODEC(ZSTD(1)),
#     `Duration` UInt64 CODEC(ZSTD(1)),
#     `StatusCode` LowCardinality(String) CODEC(ZSTD(1)),
#     `StatusMessage` String CODEC(ZSTD(1)),
#     `Events.Timestamp` Array(DateTime64(9)) CODEC(ZSTD(1)),
#     `Events.Name` Array(LowCardinality(String)) CODEC(ZSTD(1)),
#     `Events.Attributes` Array(Map(LowCardinality(String), String)) CODEC(ZSTD(1)),
#     `Links.TraceId` Array(String) CODEC(ZSTD(1)),
#     `Links.SpanId` Array(String) CODEC(ZSTD(1)),
#     `Links.TraceState` Array(String) CODEC(ZSTD(1)),
#     `Links.Attributes` Array(Map(LowCardinality(String), String)) CODEC(ZSTD(1)),
#     INDEX idx_trace_id TraceId TYPE bloom_filter(0.001) GRANULARITY 1,
#     INDEX idx_res_attr_key mapKeys(ResourceAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
#     INDEX idx_res_attr_value mapValues(ResourceAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
#     INDEX idx_span_attr_key mapKeys(SpanAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
#     INDEX idx_span_attr_value mapValues(SpanAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
#     INDEX idx_duration Duration TYPE minmax GRANULARITY 1
# )
# ENGINE = MergeTree
# ORDER BY (ServiceName, SpanName, toDateTime(Timestamp))

from agents.tracing import TracingProcessor
from datetime import datetime, timezone
from collections import defaultdict
import threading
import requests
import json
import time
import os


# ---------- helpers ----------

def _parse_iso(ts):
    if not ts:
        return None
    try:
        # spans give ISO strings; support "Z"
        return datetime.fromisoformat(str(ts).replace("Z", "+00:00")).astimezone(timezone.utc)
    except Exception:
        return None

def _fmt_dt(dt):
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%d %H:%M:%S.%f")[:-3] if dt else None

def _fmt_ts(ts):
    dt = _parse_iso(ts) if isinstance(ts, str) else ts
    return _fmt_dt(dt)

def _dur_ms(s, e):
    sdt = _parse_iso(s) if isinstance(s, str) else s
    edt = _parse_iso(e) if isinstance(e, str) else e
    if not sdt or not edt:
        return 0
    return int((edt - sdt).total_seconds() * 1000)

def _normalize_model(model_obj):
    """Convert model objects to their string representation."""
    if model_obj is None:
        return None
    if isinstance(model_obj, str):
        return model_obj
    # Handle LitellmModel and other model objects
    if hasattr(model_obj, '__class__') and 'Model' in model_obj.__class__.__name__:
        if hasattr(model_obj, 'model'):
            return getattr(model_obj, 'model')
    return str(model_obj)

def _jsonable(obj):
    """Convert arbitrary SDK objects into JSON-safe structures."""
    # Handle LitellmModel and other model objects
    if hasattr(obj, '__class__') and 'Model' in obj.__class__.__name__:
        # Try to get the model name attribute
        if hasattr(obj, 'model'):
            return getattr(obj, 'model')
        return str(obj)
    if hasattr(obj, "export") and callable(obj.export):
        try:
            return _jsonable(obj.export())
        except Exception:
            return str(obj)
    if isinstance(obj, dict):
        return {str(k): _jsonable(v) for k, v in obj.items()}
    if isinstance(obj, (list, tuple)):
        return [_jsonable(v) for v in obj]
    if isinstance(obj, datetime):
        return _fmt_dt(obj)
    if isinstance(obj, (str, int, float, bool)) or obj is None:
        return obj
    return str(obj)


# ---------- processor ----------

class ClickHouseProcessor(TracingProcessor):
    def __init__(self, batch_size=200, flush_seconds=1.0):
        self.batch_size = batch_size
        self.flush_seconds = flush_seconds

        self._buf_spans = []
        self._buf_traces = []

        # per-trace caches
        self._trace_time = defaultdict(lambda: {"min": None, "max": None})  # trace_id -> {min,max} datetimes
        self._trace_model = {}  # trace_id -> model string
        self._trace_metadata = {}  # trace_id -> metadata dict

        self._lock = threading.Lock()
        self._last_flush = time.time()

        # CH config
        self._ch_url = os.getenv("CH_URL", "http://localhost:8123")
        self._ch_db = os.getenv("CH_DB", "default")
        self._span_tbl = os.getenv("CH_SPAN_TABLE", "agent_spans")
        self._trace_tbl = os.getenv("CH_TRACE_TABLE", "agent_traces")
        self._auth = None
        if os.getenv("CH_USER") or os.getenv("CH_PASS"):
            self._auth = (os.getenv("CH_USER", "default"), os.getenv("CH_PASS", ""))

    # ---- required hooks ----

    def on_trace_start(self, trace):
        # pick up model from trace metadata if provided
        md = getattr(trace, "metadata", {}) or {}
        if isinstance(md, dict):
            m = md.get("model")
            if m:
                self._trace_model[trace.trace_id] = _normalize_model(m)
            # cache the full metadata for use in spans
            self._trace_metadata[trace.trace_id] = md

    def on_span_start(self, span):
        # no-op; timing comes from span fields on end
        pass

    def on_span_end(self, span):
        import json, re

        sd = getattr(span, "span_data", None)
        span_type = type(sd).__name__ if sd else "Unknown"

        tool_name: str | None = None
        model: str | None = None
        row_metadata = _jsonable(getattr(span, "metadata", {}) or {})

        if sd is not None:
            exp = sd.export() if hasattr(sd, "export") else None

            # ---------- Function (tool) spans ----------
            if span_type == "FunctionSpanData":
                # tool name
                tool_name = (exp or {}).get("name") or getattr(sd, "name", None)

                # derive error from multiple sources
                error_msg = None

                # 1) explicit error field (rare)
                err = (exp or {}).get("error") or getattr(sd, "error", None)
                if isinstance(err, dict):
                    error_msg = err.get("message") or str(err)
                elif isinstance(err, str):
                    error_msg = err

                # 2) parse output JSON blob (your errors live here)
                out = (exp or {}).get("output") or getattr(sd, "output", None)
                out_obj = None
                if isinstance(out, str):
                    try:
                        out_obj = json.loads(out)
                    except Exception:
                        out_obj = None
                elif isinstance(out, dict):
                    out_obj = out

                if out_obj:
                    txt = (out_obj.get("text") or out_obj.get("message") or "").strip()
                    if txt and any(k in txt.lower() for k in ("failed", "exception", "error")):
                        error_msg = error_msg or txt

                # 3) fallback: anything your wrapper stashed in span.metadata
                mderr = (getattr(span, "metadata", {}) or {}).get("error")
                if not error_msg and mderr:
                    error_msg = mderr if isinstance(mderr, str) else str(mderr)

                # write status + extras into metadata
                row_metadata = _jsonable(getattr(span, "metadata", {}) or {})
                row_metadata["status"] = "error" if error_msg else "ok"
                if error_msg:
                    row_metadata["error"] = error_msg
                    m = re.search(r"Code:\s*(\d+)", error_msg)
                    if m:
                        row_metadata["error_code"] = m.group(1)

                # (optional) persist normalized arguments for analytics
                # args_raw = (exp or {}).get("arguments")
                # if args_raw is not None:
                #     row_metadata["args_json"] = args_raw

            # ---------- LLM generation spans ----------
            elif span_type == "GenerationSpanData":
                # usually a plain string
                model = getattr(sd, "model", None) or ((exp or {}).get("model") if exp else None)
                model = _normalize_model(model)  # Convert model objects to strings
                
                # capture the output/completion
                output = getattr(sd, "output", None) or ((exp or {}).get("output") if exp else None)
                if output:
                    row_metadata["llm_output"] = output if isinstance(output, str) else str(output)
                
                # capture input prompt if available
                input_data = getattr(sd, "input", None) or ((exp or {}).get("input") if exp else None)
                if input_data:
                    row_metadata["llm_input"] = input_data if isinstance(input_data, str) else str(input_data)

            # ---------- Response spans (may carry model via Responses API) ----------
            elif span_type == "ResponseSpanData":
                # Access raw response object directly (export() doesn't include content)
                resp = getattr(sd, "response", None)
                
                if resp:
                    # Get model
                    model = _normalize_model(getattr(resp, "model", None))
                    
                    # Get output - this is a list of ResponseOutputMessage, ResponseFunctionToolCall, etc.
                    output = getattr(resp, "output", None)
                    if output and isinstance(output, list):
                        texts = []
                        for item in output:
                            # Check if it's a message with content
                            if hasattr(item, "content"):
                                content = getattr(item, "content", [])
                                if isinstance(content, list):
                                    for content_item in content:
                                        # ResponseOutputText has a 'text' attribute
                                        if hasattr(content_item, "text"):
                                            texts.append(getattr(content_item, "text", ""))
                                        elif isinstance(content_item, dict) and "text" in content_item:
                                            texts.append(content_item["text"])
                                elif isinstance(content, str):
                                    texts.append(content)
                            # Also check for direct text attribute
                            elif hasattr(item, "text"):
                                texts.append(getattr(item, "text", ""))
                        
                        if texts:
                            row_metadata["response_output"] = " ".join(texts)
            
            # ---------- Agent spans (may contain messages) ----------
            elif span_type == "AgentSpanData":
                # For top-level agent spans (no parent), copy trace metadata
                parent_id = getattr(span, "parent_id", None)
                if not parent_id:
                    trace_md = self._trace_metadata.get(span.trace_id, {})
                    if trace_md:
                        # Copy prompt from trace to span
                        if "prompt" in trace_md:
                            row_metadata["user_prompt"] = trace_md["prompt"]
                        # Optionally copy other useful trace metadata
                        if "source" in trace_md:
                            row_metadata["source"] = trace_md["source"]
                
                # Get the input (user prompt) - keeping this for potential future use
                input_data = getattr(sd, "input", None)
                if input_data:
                    # input might be a string or a dict/object with messages
                    if isinstance(input_data, str):
                        row_metadata["user_prompt"] = input_data
                    elif hasattr(input_data, "messages"):
                        # extract user messages
                        messages = getattr(input_data, "messages", [])
                        user_msgs = []
                        for msg in messages:
                            if hasattr(msg, "role") and getattr(msg, "role") == "user":
                                content = getattr(msg, "content", "")
                                if isinstance(content, str):
                                    user_msgs.append(content)
                        if user_msgs:
                            row_metadata["user_prompt"] = " ".join(user_msgs)
                    elif isinstance(input_data, dict):
                        # might be {"messages": [...]}
                        messages = input_data.get("messages", [])
                        user_msgs = []
                        for msg in messages:
                            if isinstance(msg, dict) and msg.get("role") == "user":
                                user_msgs.append(msg.get("content", ""))
                        if user_msgs:
                            row_metadata["user_prompt"] = " ".join(user_msgs)
                
                # Access raw output directly
                output = getattr(sd, "output", None)
                
                if output:
                    # output might be a Result object or dict with messages
                    if hasattr(output, "messages"):
                        messages = getattr(output, "messages", [])
                    elif isinstance(output, dict):
                        messages = output.get("messages", [])
                    else:
                        messages = []
                    
                    if messages:
                        msg_texts = []
                        for msg in messages:
                            # Handle message objects
                            if hasattr(msg, "content"):
                                content = getattr(msg, "content", "")
                            elif isinstance(msg, dict):
                                content = msg.get("content", "")
                            else:
                                content = str(msg)
                            
                            # Extract text from content
                            if isinstance(content, list):
                                for c in content:
                                    if isinstance(c, dict) and "text" in c:
                                        msg_texts.append(c["text"])
                                    elif hasattr(c, "text"):
                                        msg_texts.append(getattr(c, "text", ""))
                            elif isinstance(content, str):
                                msg_texts.append(content)
                        
                        if msg_texts:
                            row_metadata["agent_output"] = " ".join(msg_texts)
            
            # ---------- Catch-all for other span types with model field ----------
            # Handle MCPListToolsSpanData and any other span types that have a model attribute
            if not model and sd is not None:
                # Try to get model from span_data directly
                model_candidate = getattr(sd, "model", None) or ((exp or {}).get("model") if exp else None)
                if model_candidate:
                    print(f"[DEBUG] {span_type}: Found model in span_data: {type(model_candidate).__name__}")
                    model = _normalize_model(model_candidate)
                    print(f"[DEBUG] {span_type}: After normalization: {model}")

        # ---- fallback to trace-level model if span didn't expose it ----
        if not model:
            model = self._trace_model.get(span.trace_id)
            if model:
                print(f"[DEBUG] {span_type}: Using trace fallback: {type(model).__name__} = {repr(model)[:100]}")
        
        # Ensure model is always a string
        pre_norm = model
        model = _normalize_model(model)
        if pre_norm and type(pre_norm).__name__ != 'str':
            print(f"[DEBUG] {span_type}: Final normalization: {type(pre_norm).__name__} -> {model}")

        # remember discovered model for siblings in the same trace
        if model and span.trace_id not in self._trace_model:
            self._trace_model[span.trace_id] = model

        # ---- track min/max per-trace timings ----
        s = _parse_iso(getattr(span, "started_at", None))
        e = _parse_iso(getattr(span, "ended_at", None))
        tt = self._trace_time[span.trace_id]
        if s and (tt["min"] is None or s < tt["min"]):
            tt["min"] = s
        if e and (tt["max"] is None or e > tt["max"]):
            tt["max"] = e

        # ---- emit row ----
        print(f"[DEBUG] {span_type}: Final model value before row creation: {type(model).__name__} = {repr(model)[:100]}")
        row = {
            "trace_id": span.trace_id,
            "span_id": span.span_id,
            "parent_id": getattr(span, "parent_id", "") or "",
            "span_type": span_type,
            "started_at": _fmt_ts(getattr(span, "started_at", None)),
            "ended_at": _fmt_ts(getattr(span, "ended_at", None)),
            "duration_ms": _dur_ms(getattr(span, "started_at", None), getattr(span, "ended_at", None)),
            "model": model,
            "tool_name": tool_name,
            "metadata": row_metadata,          # includes status/error if FunctionSpanData
            "span_data": _jsonable(sd),
        }

        with self._lock:
            self._buf_spans.append(row)
            self._maybe_flush()



    def on_trace_end(self, trace):
        tt = self._trace_time.get(trace.trace_id, {"min": None, "max": None})
        row = {
            "trace_id": trace.trace_id,
            "workflow_name": getattr(trace, "name", None),
            "group_id": getattr(trace, "group_id", None),
            "started_at": _fmt_dt(tt["min"]),
            "ended_at": _fmt_dt(tt["max"]),
            "duration_ms": int(((tt["max"] - tt["min"]).total_seconds()) * 1000) if tt["min"] and tt["max"] else 0,
            "metadata": _jsonable(getattr(trace, "metadata", {}) or {}),
        }

        with self._lock:
            self._buf_traces.append(row)
            self._maybe_flush(force=True)

        # cleanup caches for this trace
        self._trace_time.pop(trace.trace_id, None)
        self._trace_model.pop(trace.trace_id, None)
        self._trace_metadata.pop(trace.trace_id, None)

    def shutdown(self):
        with self._lock:
            self._flush()

    def force_flush(self):
        with self._lock:
            self._flush()

    # ---- batching / I/O ----

    def _maybe_flush(self, force=False):
        if force or (len(self._buf_spans) + len(self._buf_traces) >= self.batch_size) \
           or ((time.time() - self._last_flush) >= self.flush_seconds):
            self._flush()
            self._last_flush = time.time()

    def _dump_rows(self, rows):
        safe_rows = [_jsonable(r) for r in rows]
        return "\n".join(json.dumps(r, ensure_ascii=False) for r in safe_rows) + "\n"

    def _flush(self):
        if not self._buf_spans and not self._buf_traces:
            return
        try:
            if self._buf_spans:
                body = self._dump_rows(self._buf_spans)
                requests.post(
                    f"{self._ch_url}/?database={self._ch_db}",
                    params={"query": f"INSERT INTO {self._span_tbl} FORMAT JSONEachRow"},
                    data=body.encode("utf-8"),
                    auth=self._auth,
                    timeout=5,
                )
                self._buf_spans.clear()

            if self._buf_traces:
                body = self._dump_rows(self._buf_traces)
                requests.post(
                    f"{self._ch_url}/?database={self._ch_db}",
                    params={"query": f"INSERT INTO {self._trace_tbl} FORMAT JSONEachRow"},
                    data=body.encode("utf-8"),
                    auth=self._auth,
                    timeout=5,
                )
                self._buf_traces.clear()
        except Exception as e:
            print(f"[ClickHouseProcessor] flush error: {e}")