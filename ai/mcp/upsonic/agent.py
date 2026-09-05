# /// script
# requires-python = ">=3.13"
# dependencies = [
#   "mcp==1.28.1",
#   "fastmcp==3.4.7",
#   "upsonic[mcp,sqlite-storage]==0.77.3",
#   "openai==3.8.0",
# ]
# ///

import os

from upsonic import Agent, Task
from upsonic.models.openai import OpenAIResponsesModel

env = {
    "CLICKHOUSE_HOST": os.getenv("CLICKHOUSE_HOST", 'sql-clickhouse.clickhouse.com'),
    "CLICKHOUSE_PORT": os.getenv("CLICKHOUSE_PORT", '8443'),
    "CLICKHOUSE_USER": os.getenv("CLICKHOUSE_USER", 'demo'),
    "CLICKHOUSE_PASSWORD": os.getenv("CLICKHOUSE_PASSWORD", ''),
    "CLICKHOUSE_SECURE": os.getenv("CLICKHOUSE_SECURE", 'true'),
    "CLICKHOUSE_VERIFY": os.getenv("CLICKHOUSE_VERIFY", 'true'),
    "CLICKHOUSE_CONNECT_TIMEOUT": os.getenv("CLICKHOUSE_CONNECT_TIMEOUT", '30'),
    "CLICKHOUSE_SEND_RECEIVE_TIMEOUT": os.getenv("CLICKHOUSE_SEND_RECEIVE_TIMEOUT", '30')
}

class DatabaseMCP:
    """
    MCP server for ClickHouse database operations.
    Provides tools for querying tables and databases
    """
    command="uv"
    args=["tool", "run", "--python", "3.13", "--from", "mcp-clickhouse==0.6.0", "mcp-clickhouse"]
    env=env


database_agent = Agent(
    name="Data Analyst",
    role="ClickHouse specialist.",
    goal="Query ClickHouse database and tables and answer questions",
    model=OpenAIResponsesModel(model_name=os.getenv("OPENAI_MODEL", "gpt-5.6-luna"))
)


async def main():
    from upsonic.tools.mcp import MCPHandler
    async with MCPHandler(config=DatabaseMCP, timeout_seconds=60) as clickhouse:
        task = Task(
            description=os.getenv("MCP_PROMPT", "Tell me about the UK property market in the 2020s. Use ClickHouse."),
            tools=[clickhouse],
        )
        result = await database_agent.do_async(task)
        print(result)

if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
