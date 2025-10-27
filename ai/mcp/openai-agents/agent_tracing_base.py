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
from agents.tracing import add_trace_processor
from agents.tracing.processors import BatchTraceProcessor
from utils import simple_render_chunk
from agents.tracing.processors import TracingExporter

class ClickHouseExporter(TracingExporter):    
    def export(self, items: list) -> None:
        for item in items:
            if "Span" in type(item).__name__:                
                span_data = {}
                if hasattr(item, "span_data") and item.span_data:
                    if hasattr(item.span_data, "export"):
                        span_data = item.span_data.export()
                    
                    # Extract model - not included in export() by default
                    if hasattr(item.span_data, "response") and item.span_data.response:
                        if hasattr(item.span_data.response, "model"):
                            span_data["model"] = str(item.span_data.response.model)
                
                span_export = {**item.export(), "span_data": span_data}
                print(span_export)
            else:
                print(item.export())

# class ClickHouseExporter(TracingExporter):    
#     def export(self, items: list) -> None:
#         for item in items:
#             print(item.export())

async def main():
    exporter = ClickHouseExporter()
    add_trace_processor(BatchTraceProcessor(exporter=exporter, max_batch_size=200))

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

            with trace("Agent workflow"):
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