# /// script
# requires-python = ">=3.13"
# dependencies = [
#   "openai-agents==0.22.0",
# ]
# ///

import os

env = {
    "CLICKHOUSE_HOST": os.getenv("CLICKHOUSE_HOST", 'sql-clickhouse.clickhouse.com'),
    "CLICKHOUSE_PORT": os.getenv("CLICKHOUSE_PORT", '8443'),
    "CLICKHOUSE_USER": os.getenv("CLICKHOUSE_USER", 'demo'),
    "CLICKHOUSE_PASSWORD": os.getenv("CLICKHOUSE_PASSWORD", ''),
    "CLICKHOUSE_SECURE": os.getenv("CLICKHOUSE_SECURE", 'true')
}

from agents.mcp import MCPServerStdio
from agents import Agent, Runner, RunConfig
import asyncio
from utils import simple_render_chunk


async def main(tracing_disabled=True):
    async with MCPServerStdio(
            name="ClickHouse SQL Playground",
            params={
                "command": "uv",
                "args": ["tool", "run", "--python", "3.13", "--from", "mcp-clickhouse==0.6.0", "mcp-clickhouse"],
                "env": env,
            },
            client_session_timeout_seconds=60,
            cache_tools_list=True,  # avoid re-listing tools on every step
        ) as server:
            agent = Agent(
                name="Assistant",
                instructions="Use the tools to query ClickHouse and answer questions based on the query results.",
                mcp_servers=[server],
                model=os.getenv("OPENAI_MODEL", "gpt-5.6-luna"),
            )

            message = os.getenv("MCP_PROMPT", "What's the most popular GitHub project for each month in 2025?")
            print(f"\n\nRunning: {message}")

            result = Runner.run_streamed(
                starting_agent=agent,
                input=message,
                max_turns=20,
                run_config=RunConfig(
                    tracing_disabled=tracing_disabled,
                ),
            )
            async for chunk in result.stream_events():
                simple_render_chunk(chunk)

if __name__ == "__main__":
    asyncio.run(main())
