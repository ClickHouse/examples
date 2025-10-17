# /// script
# requires-python = ">=3.9"
# dependencies = [
#   "openai-agents",
#   "litellm"
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
from agents.tracing import add_trace_processor
from agents.tracing.processors import BatchTraceProcessor
from clickhouse_processor import ClickHouseProcessor, ClickHouseExporter
from utils import simple_render_chunk
from agents.extensions.models.litellm_model import LitellmModel

async def main():

    # Use BatchTraceProcessor with ClickHouseExporter
    exporter = ClickHouseExporter()
    add_trace_processor(BatchTraceProcessor(exporter=exporter, max_batch_size=200))

    # Or use the standalone ClickHouseProcessor (handles its own batching)
    # add_trace_processor(ClickHouseProcessor(batch_size=200, flush_seconds=1.0))

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

            model = LitellmModel(
                model="anthropic/claude-sonnet-4-20250514",
            )

            agent = Agent(
                name="Assistant",
                instructions="Use the tools to query ClickHouse and answer questions based on those files.",
                mcp_servers=[server],
                model="gpt-5-mini-2025-08-07", 
                # model=model,
                # model="gpt-4.1-mini"
            )

            message = "What's the most popular GitHub project for each month in 2025?"
            # message = "Run a query that will definitely fail: SELECT 1/0 FROM system.one WHERE 1=0"
            print(f"\n\nRunning: {message}")

            # --- trace the whole run (gives you trace.name and optional group correlation) ---
            # Convert model to string to avoid JSON serialization errors
            # Try to get the model name attribute first, then fall back to string conversion
            if isinstance(agent.model, str):
                model_str = agent.model
            elif hasattr(agent.model, 'model'):
                model_str = getattr(agent.model, 'model')
            else:
                model_str = str(agent.model)
            with trace("Agent workflow", group_id="conv_demo_001", metadata={"source": "cli", "model": model_str, "prompt": message}):
                result = Runner.run_streamed(
                    starting_agent=agent,
                    input=message,
                    max_turns=20,
                    run_config=RunConfig(
                        trace_include_sensitive_data=True,  # set True if you want full inputs/outputs
                    ),
                )
                async for chunk in result.stream_events():
                    # Assumes you already have this utility. If not, replace with a simple print.
                    simple_render_chunk(chunk)

asyncio.run(main())