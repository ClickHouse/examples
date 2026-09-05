"""Run with one framework's dependencies: python tests/framework_smoke.py agno.
Exercises the notebook's configuration and native tool adapter, without an LLM.
"""
import ast
import asyncio
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
CELLS = {
    "agno": [5, 8, 10],
    "claude-agent": [4, 7, 8],
    "crewai": [5, 8, 10, 11],
    "dspy": [5, 8, 10, 11, 13, 15],
    "langchain": [5, 8, 9],
    "llamaindex": [5, 8, 9, 12, 13, 16],
    "mcp-agent": [3, 5, 8, 10],
    "microsoft-agent-framework": [3, 5, 7],
    "openai-agents": [5, 8, 10],
    "pydanticai": [5, 8, 10, 11],
    "upsonic": [5, 8, 10, 11, 12],
}
QUERY = {"query": "SELECT 1 AS value"}
def verify(result):
    if hasattr(result, "isError"):
        assert not result.isError, result
    if hasattr(result, "is_error"):
        assert not result.is_error, result
    payload = result
    for _ in range(8):
        if isinstance(payload, dict) and "rows" in payload:
            break
        if hasattr(payload, "raw_output"):
            payload = payload.raw_output
        elif hasattr(payload, "content"):
            payload = payload.content
        elif isinstance(payload, dict):
            payload = payload.get("result", payload.get("content", payload.get("structuredContent")))
        elif isinstance(payload, (list, tuple)):
            payload = payload[0]
        elif isinstance(payload, str):
            payload = json.loads(payload)
        else:
            raise AssertionError(payload)
        if isinstance(payload, dict) and "text" in payload:
            payload = payload["text"]
        elif hasattr(payload, "text"):
            payload = payload.text

    assert payload["rows"] == [[1]], payload

async def main(name):
    os.environ.setdefault("OPENAI_API_KEY", "unused-smoke-test-key")
    os.environ.setdefault("ANTHROPIC_API_KEY", "unused-smoke-test-key")
    for key, value in {"CLICKHOUSE_HOST": "localhost", "CLICKHOUSE_PORT": "8123",
                       "CLICKHOUSE_USER": "default", "CLICKHOUSE_PASSWORD": "", "CLICKHOUSE_SECURE": "false"}.items():
        os.environ.setdefault(key, value)
    if name in CELLS:
        notebook = json.loads(next((ROOT / name).glob("*.ipynb")).read_text())
        scope = {"__name__": "framework_smoke"}
        sys.path.insert(0, str(ROOT / name))
        for index in CELLS[name]:
            exec("".join(notebook["cells"][index]["source"]), scope)
    if name == "agno":
        async with scope["MCPTools"](command="uv tool run --python 3.13 --from mcp-clickhouse==0.6.0 mcp-clickhouse", env=scope["env"], timeout_seconds=60) as tools:
            agent = scope["Agent"](model=scope["Claude"](id=os.getenv("ANTHROPIC_MODEL", "claude-sonnet-5")), tools=[tools])
            verify(await tools.session.call_tool("run_query", QUERY))
    elif name == "crewai":
        with scope["MCPServerAdapter"](scope["server_params"], connect_timeout=60) as tools:
            tool = next(t for t in tools if t.name == "run_query")
            verify(tool.run(**QUERY))
    elif name == "dspy":
        async with scope["stdio_client"](scope["server_params"]) as (read, write):
            async with scope["ClientSession"](read, write) as session:
                await session.initialize()
                tool = next(t for t in (await session.list_tools()).tools if t.name == "run_query")
                wrapped = scope["dspy"].Tool.from_mcp_tool(session, tool)
                verify(await wrapped.acall(**QUERY))
    elif name == "langchain":
        async with scope["adapter"]:
            tools = await scope["adapter"].list_tools()
            scope["create_agent"](scope["ChatAnthropic"](model="claude-sonnet-5"), tools)
            verify(await next(t for t in tools if t.name.endswith("run_query")).ainvoke(QUERY))
    elif name == "llamaindex":
        tools = await scope["mcp_tool_spec"].to_tool_list_async()
        scope["FunctionAgent"](tools=tools, llm=scope["llm"])
        verify(await next(t for t in tools if t.metadata.name == "run_query").acall(**QUERY))
    elif name == "pydanticai":
        async with scope["agent"]:
            verify(await scope["server"].client.call_tool("run_query", QUERY))
    elif name == "microsoft-agent-framework":
        async with scope["clickhouse_mcp_server"] as tool:
            scope["Agent"](client=scope["OpenAIChatClient"](model="gpt-5.6-luna"), tools=tool)
            verify(await tool.call_tool("run_query", **QUERY))
    elif name == "openai-agents":
        async with scope["MCPServerStdio"](params={
            "command": "uv", "args": ["tool", "run", "--python", "3.13", "--from", "mcp-clickhouse==0.6.0", "mcp-clickhouse"],
            "env": scope["env"]}, client_session_timeout_seconds=60) as server:
            scope["Agent"](name="test", model="gpt-5.6-luna", mcp_servers=[server])
            verify(await server.call_tool("run_query", QUERY))
    elif name == "mcp-agent":
        async with scope["app"].run():
            async with scope["Agent"](name="test", server_names=["clickhouse"]) as agent:
                listed = await agent.list_tools()
                tool = next(t for t in listed.tools if t.name.endswith("run_query"))
                verify(await agent.call_tool(tool.name, QUERY))
    elif name == "upsonic":
        from upsonic.tools.mcp import MCPHandler
        async with MCPHandler(config=scope["DatabaseMCP"], timeout_seconds=60) as handler:
            verify(await handler.call_tool("run_query", QUERY))
    elif name == "google-agent-development-kit":
        sys.path.insert(0, str(ROOT / name))
        from mcp_agent.agent import root_agent
        toolset = root_agent.tools[0]
        try:
            tools = await toolset.get_tools()
            query = next(t for t in tools if t.name == "run_query")
            result = await query.run_async(args=QUERY, tool_context=None)
            verify(result)
        finally:
            await toolset.close()
    elif name == "claude-agent":
        # Inspect the executable allowlist, then query using its exact stdio configuration.
        from mcp import ClientSession, StdioServerParameters
        from mcp.client.stdio import stdio_client
        config = scope["options"].mcp_servers["mcp-clickhouse"]
        assert "mcp__mcp-clickhouse__run_query" in scope["options"].allowed_tools
        async with stdio_client(StdioServerParameters(**config)) as (read, write):
            async with ClientSession(read, write) as session:
                await session.initialize()
                verify(await session.call_tool("run_query", QUERY))
    else:
        raise ValueError(name)
    print(json.dumps({"framework": name, "status": "passed", "check": "native MCP adapter SELECT 1; no model call"}))

if __name__ == "__main__":
    asyncio.run(main(sys.argv[1]))
