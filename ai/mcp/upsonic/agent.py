# /// script
# requires-python = ">=3.9"
# dependencies = [
#   "upsonic",
#   "asyncpg", "aiosqlite"
# ]
# ///

from upsonic import Agent, Task

class DatabaseMCP:
    """
    MCP server for ClickHouse database operations.
    Provides tools for querying tables and databases
    """
    command="uv"
    args=[
        "run",
        "--with",
        "mcp-clickhouse",
        "--python",
        "3.10",
        "mcp-clickhouse"
    ]
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


database_agent = Agent(
    name="Data Analyst",
    role="ClickHouse specialist.",
    goal="Query ClickHouse database and tables and answer questions",
    model="openai/o3-mini"
)


task = Task(
    description="Tell me what happened in the UK property market in the 2020s. Use ClickHouse.",
    tools=[DatabaseMCP]
)

# Execute the workflow
workflow_result = database_agent.do(task)
print("\nMulti-MCP Workflow Result:")
print(workflow_result)