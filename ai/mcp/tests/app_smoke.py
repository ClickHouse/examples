"""Offline regression checks; run with the selected app's requirements."""
import asyncio
import importlib.util
import os
from pathlib import Path
import sys
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

ROOT = Path(__file__).resolve().parents[1]
os.environ.setdefault("ANTHROPIC_API_KEY", "unused-test-key")

def load(name, filename):
    path = ROOT / name / filename
    os.chdir(path.parent)
    sys.path.insert(0, str(path.parent))
    spec = importlib.util.spec_from_file_location("example_app", path)
    app = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(app)
    return app

async def chainlit():
    app = load("chainlit", "chat_mcp.py")
    from anthropic.types import TextBlock, ThinkingBlock, ToolUseBlock
    from mcp.types import CallToolResult, TextContent
    from mcp import ClientSession, StdioServerParameters
    from mcp.client.stdio import stdio_client
    import shlex

    # Load the committed Chainlit 2.12 config and its actual subprocess settings.
    cfg = app.config.features.mcp
    assert cfg.enabled and len(cfg.servers) == 1
    server = cfg.servers[0]
    command, *args = shlex.split(server.command)
    async with stdio_client(StdioServerParameters(command=command, args=args, env=server.env)) as streams:
        async with ClientSession(*streams) as session:
            await session.initialize()
            tools = await session.list_tools()
            assert "run_query" in {t.name for t in tools.tools}
            result = await session.call_tool("run_query", {"query": "SELECT 1 AS ok"})
            assert not result.isError

    state = {"chat_messages": [], "mcp_tools": {"clickhouse": [{"name": "run_query"}]}}
    fake_session = AsyncMock()
    fake_session.call_tool.side_effect = [
        CallToolResult(content=[TextContent(type="text", text="250")]),
        CallToolResult(content=[TextContent(type="text", text="bad SQL")], isError=True),
        RuntimeError("connection closed"),
    ]
    context = SimpleNamespace(current_step=SimpleNamespace(name="", output=""),
                              session=SimpleNamespace(mcp_sessions={"clickhouse": (fake_session, None)}))
    responses = [
        SimpleNamespace(content=[
            ThinkingBlock(type="thinking", thinking="Inspecting data", signature="test-signature"),
            ToolUseBlock(type="tool_use", id="one", name="run_query", input={"query": "SELECT 250"}),
            ToolUseBlock(type="tool_use", id="two", name="run_query", input={"query": "invalid SQL"}),
        ]),
        SimpleNamespace(content=[TextBlock(type="text", text="The second query failed.")]),
    ]
    user_session = SimpleNamespace(get=state.get, set=lambda key, value: state.update({key: value}))
    # The step decorator only supplies UI context; exercise its actual tool body.
    tool_body = app.call_tool.__wrapped__
    with patch.object(app.cl, "user_session", user_session), patch.object(app.cl, "context", context), \
         patch.object(app, "call_claude", AsyncMock(side_effect=responses)), \
         patch.object(app, "call_tool", tool_body):
        await app.on_message(SimpleNamespace(content="Compare two queries"))
        history = state["chat_messages"]
        assert [m["role"] for m in history] == ["user", "assistant", "user", "assistant"]
        assert history[1]["content"][0]["signature"] == "test-signature"
        assert [r["tool_use_id"] for r in history[2]["content"]] == ["one", "two"]
        assert [r["is_error"] for r in history[2]["content"]] == [False, True]
        failed = await tool_body(ToolUseBlock(type="tool_use", id="three", name="run_query", input={}))
        assert failed["is_error"] and "connection closed" in failed["content"]
        await app.on_mcp_disconnect("clickhouse", fake_session)
        missing = await tool_body(ToolUseBlock(type="tool_use", id="four", name="run_query", input={}))
        assert missing["is_error"]
        assert not state["mcp_tools"]
    print("PASS Chainlit: configured MCP query, multiple tool results, thinking, errors, disconnect")


async def chainlit_openai():
    app = load("chainlit", "chat_openai.py")
    import json
    state = {"chat_messages": [], "mcp_tools": {"clickhouse": [{
        "name": "run_query", "description": "Query ClickHouse",
        "input_schema": {"type": "object", "properties": {"query": {"type": "string"}}},
    }]}}
    user_session = SimpleNamespace(get=state.get, set=lambda key, value: state.update({key: value}))
    sent = []
    class Message:
        def __init__(self, content):
            self.content = content
        async def stream_token(self, text):
            self.content += text
        async def send(self):
            sent.append(self.content)
    def call(index, identifier=None, arguments="", name=None):
        return SimpleNamespace(index=index, id=identifier,
            function=SimpleNamespace(name=name, arguments=arguments))
    def chunk(content=None, calls=None):
        return SimpleNamespace(choices=[SimpleNamespace(
            delta=SimpleNamespace(content=content, tool_calls=calls))])
    streams = [
        [chunk(calls=[
            call(1, "second", '{"query":', "run_query"),
            call(0, "first", '{"query":"SELECT ', "run_query"),
            call(2, "malformed", '{broken', "run_query"),
        ]), chunk(calls=[
            call(0, arguments='250"}'), call(1, arguments='"invalid SQL"}'),
        ])],
        [chunk(content="North 250; "), chunk(content="the second query failed.")],
        [chunk(content="The earlier answer was North 250.")],
    ]
    requests = []
    class Client:
        def __init__(self):
            self.chat = SimpleNamespace(completions=self)
        async def __aenter__(self):
            return self
        async def __aexit__(self, *args):
            return False
        async def create(self, **kwargs):
            requests.append(json.loads(json.dumps(kwargs)))
            events = streams.pop(0)
            async def iterate():
                for event in events:
                    yield event
            return iterate()
    tool = AsyncMock(side_effect=[
        {"content": "250", "is_error": False},
        {"content": "bad SQL", "is_error": True},
    ])
    with patch.object(app.cl, "user_session", user_session), \
         patch.object(app.cl, "Message", Message), \
         patch.object(app, "AsyncOpenAI", Client), patch.object(app, "call_tool", tool):
        await app.on_message(SimpleNamespace(content="Compare the queries"))
        history = state["chat_messages"]
        assert [c["id"] for c in history[1]["tool_calls"]] == ["first", "second", "malformed"]
        assert tool.await_args_list[0].args[0].input == {"query": "SELECT 250"}
        assert tool.await_args_list[1].args[0].input == {"query": "invalid SQL"}
        assert tool.await_count == 2
        assert [m["tool_call_id"] for m in history[2:5]] == ["first", "second", "malformed"]
        assert json.loads(history[3]["content"])["error"] == "bad SQL"
        assert "error" in json.loads(history[4]["content"])
        await app.on_message(SimpleNamespace(content="Repeat the earlier answer"))
        assert len(requests[2]["messages"]) == 7
        assert requests[2]["messages"][0]["content"] == "Compare the queries"
        assert sent == ["North 250; the second query failed.", "The earlier answer was North 250."]
    print("PASS Chainlit OpenAI: interleaved argument fragments, tool ordering, errors and history")

async def streamlit():
    app = load("streamlit", "app.py")
    async def failed(messages):
        assert messages[-1]["content"] == "question"
        yield "partial"
        raise RuntimeError("test stream failure")
    with patch.object(app, "stream_clickhouse_agent", failed):
        stream = app.run_agent_query_sync([{"role": "user", "content": "question"}])
        assert next(stream) == "partial"
        try:
            next(stream)
        except RuntimeError as exc:
            assert str(exc) == "test stream failure"
        else:
            raise AssertionError("stream failure was swallowed")
    print("PASS Streamlit: partial stream and failure propagation")

async def slackbot():
    app = load("slackbot", "main.py")
    spec = {"$schema": "https://vega.github.io/schema/vega-lite/v5.json",
            "data": {"values": [{"region": "North", "revenue": 250}]}, "mark": "bar",
            "encoding": {"x": {"field": "region", "type": "nominal"},
                         "y": {"field": "revenue", "type": "quantitative"}}}
    import json
    assert app.extract_vega_lite_specs("Result\n```json\n" + json.dumps(spec) + "\n```") == [spec]
    client = AsyncMock()
    async def upload(**kwargs):
        content = Path(kwargs["file"]).read_bytes()
        assert content.startswith(b"\x89PNG")
        return {"ok": True}
    client.files_upload_v2.side_effect = upload
    await app.render_and_upload_chart(client, "test-channel", "1.0", spec)
    client.files_upload_v2.assert_awaited_once()
    chart_path = Path(client.files_upload_v2.call_args.kwargs["file"])
    assert not chart_path.exists()
    client.files_upload_v2.side_effect = RuntimeError("test upload failure")
    try:
        await app.render_and_upload_chart(client, "test-channel", "1.0", spec)
    except RuntimeError:
        assert not Path(client.files_upload_v2.call_args.kwargs["file"]).exists()
    else:
        raise AssertionError("upload failure was swallowed")
    say = AsyncMock()
    class FailedAgent:
        async def __aenter__(self):
            return self
        async def __aexit__(self, *args):
            return False
        async def run(self, prompt):
            raise RuntimeError("test query failure")
    with patch.object(app, "agent", FailedAgent()):
        await app.handle_slack_query({"user": "test", "text": "query", "ts": "1", "channel": "test"}, say)
    assert "query failed" in say.call_args.kwargs["text"]
    print("PASS Slack: real PNG rendering, mocked upload, cleanup and visible query failure")

asyncio.run({"chainlit": chainlit, "chainlit-openai": chainlit_openai, "streamlit": streamlit, "slackbot": slackbot}[sys.argv[1]]())
