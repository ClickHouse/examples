# /// script
# requires-python = ">=3.9"
# dependencies = [
#   "openai-agents",
#   "clickhouse-connect",
# ]
# ///

env = {
    "CLICKHOUSE_HOST": "sql-clickhouse.clickhouse.com",
    "CLICKHOUSE_PORT": "8443",
    "CLICKHOUSE_USER": "demo",
    "CLICKHOUSE_PASSWORD": "",
    "CLICKHOUSE_SECURE": "true"
}

from agents.mcp import MCPServerStdio
from agents import Agent, Runner, trace, RunConfig
import asyncio
from utils import simple_render_chunk


async def main():    
    async with MCPServerStdio(
            name="ClickHouse SQL Playground",
            params={
                "command": "uv",
                "args": [
                    "run",
                    "--with", "mcp-clickhouse",
                    "--python", "3.13",
                    "mcp-clickhouse",
                ],
                "env": env,
            },
            client_session_timeout_seconds=60,
            cache_tools_list=True,  # avoid re-listing tools on every step
        ) as server:
            agent = Agent(
                name="Assistant",
                instructions="Use the tools to query ClickHouse and answer questions based on those files.",
                mcp_servers=[server],
                model="gpt-5-mini-2025-08-07",
            )

            message = "What's the most popular GitHub project for each month in 2025?"
            print(f"\n\nRunning: {message}")

            result = Runner.run_streamed(
                starting_agent=agent,
                input=message,
                max_turns=20,
                run_config=RunConfig(
                    trace_include_sensitive_data=True,
                ),
            )
            async for chunk in result.stream_events():
                simple_render_chunk(chunk)

asyncio.run(main())