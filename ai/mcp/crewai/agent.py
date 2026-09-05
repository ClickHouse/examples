# /// script
# requires-python = ">=3.13"
# dependencies = [
#   "crewai==1.15.20",
#   "crewai-tools[mcp]==1.15.20",
# ]
# ///

import os

from crewai import Agent
from crewai_tools import MCPServerAdapter
from mcp import StdioServerParameters

env={
    "CLICKHOUSE_HOST": os.getenv("CLICKHOUSE_HOST", 'sql-clickhouse.clickhouse.com'),
    "CLICKHOUSE_PORT": os.getenv("CLICKHOUSE_PORT", '8443'),
    "CLICKHOUSE_USER": os.getenv("CLICKHOUSE_USER", 'demo'),
    "CLICKHOUSE_PASSWORD": os.getenv("CLICKHOUSE_PASSWORD", ''),
    "CLICKHOUSE_SECURE": os.getenv("CLICKHOUSE_SECURE", 'true'),
    "CLICKHOUSE_VERIFY": os.getenv("CLICKHOUSE_VERIFY", 'true'),
    "CLICKHOUSE_CONNECT_TIMEOUT": os.getenv("CLICKHOUSE_CONNECT_TIMEOUT", '30'),
    "CLICKHOUSE_SEND_RECEIVE_TIMEOUT": os.getenv("CLICKHOUSE_SEND_RECEIVE_TIMEOUT", '30')
}

server_params=StdioServerParameters(
    command='uv',
    args=["tool", "run", "--python", "3.13", "--from", "mcp-clickhouse==0.6.0", "mcp-clickhouse"],
    env=env
)

with MCPServerAdapter(server_params, connect_timeout=60) as mcp_tools:
    print(f"Available tools: {[tool.name for tool in mcp_tools]}")

    my_agent = Agent(
        llm=os.getenv("OPENAI_MODEL", "gpt-5.6-luna"),
        role="MCP Tool User",
        goal="Utilize tools from an MCP server.",
        backstory="I can connect to MCP servers and use their tools.",
        tools=mcp_tools,
        reasoning=True,
        verbose=True
    )
    my_agent.kickoff(messages=[
        {"role": "user", "content": os.getenv("MCP_PROMPT", "Tell me about property prices in London between 2024 and 2025")}
    ])
