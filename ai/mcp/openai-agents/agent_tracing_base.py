# /// script
# requires-python = ">=3.13"
# dependencies = ["openai-agents==0.22.0"]
# ///
"""Print trace records to stdout; agent_tracing.py stores them in ClickHouse."""
import asyncio
import json
from agents import trace
from agents.tracing import set_trace_processors
from agents.tracing.processors import BatchTraceProcessor, TracingExporter
from agent_no_tracing import main as run_agent

class ConsoleExporter(TracingExporter):
    def export(self, items):
        for item in items:
            print(json.dumps(item.export(), default=str))

async def main():
    processor = BatchTraceProcessor(exporter=ConsoleExporter())
    set_trace_processors([processor])
    try:
        with trace("ClickHouse analyst"):
            await run_agent(tracing_disabled=False)
    finally:
        processor.force_flush()
        processor.shutdown()

if __name__ == "__main__":
    asyncio.run(main())
