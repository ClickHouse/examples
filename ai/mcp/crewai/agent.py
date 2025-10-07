# /// script
# requires-python = ">=3.9"
# dependencies = [
#   "crewai-tools[mcp]",
# ]
# ///

from crewai import Agent
from crewai_tools import MCPServerAdapter
from mcp import StdioServerParameters

server_params=StdioServerParameters(
    command='uv',
    args=[
        "run",
        "--with", "mcp-clickhouse",
        "--python", "3.10",
        "mcp-clickhouse"
    ],
    env={
        "CLICKHOUSE_HOST": "sql-clickhouse.clickhouse.com",
        "CLICKHOUSE_PORT": "8443",
        "CLICKHOUSE_USER": "demo",
        "CLICKHOUSE_PASSWORD": "",
        "CLICKHOUSE_SECURE": "true",
        "CLICKHOUSE_VERIFY": "true",
        "CLICKHOUSE_CONNECT_TIMEOUT": "30",
        "CLICKHOUSE_SEND_RECEIVE_TIMEOUT": "30"
    }
)

with MCPServerAdapter(server_params, connect_timeout=60) as mcp_tools:
    print(f"Available tools: {[tool.name for tool in mcp_tools]}")

    my_agent = Agent(
        role="MCP Tool User",
        goal="Utilize tools from an MCP server.",
        backstory="I can connect to MCP servers and use their tools.",
        tools=mcp_tools,
        reasoning=True,
        verbose=True
    )
    my_agent.kickoff(messages=[
        {"role": "user", "content": "Tell me about property prices in London between 2024 and 2025"}
    ])