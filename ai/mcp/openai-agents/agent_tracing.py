# /// script
# requires-python = ">=3.13"
# dependencies = ["openai-agents==0.22.0"]
# ///
import asyncio
from agents import trace
from agents.tracing import set_trace_processors
from agents.tracing.processors import BatchTraceProcessor
from agent_no_tracing import main as run_agent
from clickhouse_processor import ClickHouseExporter

async def main():
    exporter = ClickHouseExporter()
    processor = BatchTraceProcessor(exporter=exporter, max_batch_size=200)
    set_trace_processors([processor])
    try:
        with trace("ClickHouse analyst"):
            await run_agent(tracing_disabled=False)
    finally:
        processor.force_flush()
        processor.shutdown()
        exporter.raise_if_failed()

if __name__ == "__main__":
    asyncio.run(main())
