# /// script
# requires-python = ">=3.13"
# dependencies = ["fastmcp==4.0.3"]
# ///
"""Check ClickHouse MCP without an LLM: uv run smoke_test.py [--url URL]."""
import argparse
import asyncio
import json
import os

from fastmcp import Client
from fastmcp.client.transports import StdioTransport

def connection_env():
    defaults = {
        "CLICKHOUSE_HOST": "localhost", "CLICKHOUSE_PORT": "8123",
        "CLICKHOUSE_USER": "default", "CLICKHOUSE_PASSWORD": "",
        "CLICKHOUSE_SECURE": "false", "CLICKHOUSE_VERIFY": "true",
    }
    return {key: os.getenv(key, value) for key, value in defaults.items()}

def decode(result):
    text = next(block.text for block in result.content if block.type == "text")
    return json.loads(text)

async def check(client):
    async with client:
        names = {tool.name for tool in await client.list_tools()}
        assert {"list_databases", "list_tables", "run_query"} <= names, names
        databases = decode(await client.call_tool("list_databases", {}))
        assert "system" in databases, databases
        first = decode(await client.call_tool("list_tables", {
            "database": "system", "page_size": 1, "include_detailed_columns": False,
        }))
        assert len(first["tables"]) == 1 and first["next_page_token"], first
        second = decode(await client.call_tool("list_tables", {
            "database": "system", "page_size": 1, "page_token": first["next_page_token"],
            "include_detailed_columns": False,
        }))
        assert first["tables"][0]["name"] != second["tables"][0]["name"]
        result = decode(await client.call_tool("run_query", {"query": "SELECT 1 AS value, version() AS version"}))
        assert result["rows"][0][0] == 1, result
        invalid = await client.call_tool("run_query", {"query": "SELECT missing_column FROM system.one"}, raise_on_error=False)
        assert invalid.is_error, invalid
        print(json.dumps({"status": "passed", "tools": sorted(names), "clickhouse": result["rows"][0][1],
                          "checks": ["discovery", "databases", "pagination", "query", "query error"]}))

async def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", help="Streamable HTTP endpoint, for example http://localhost:8000/mcp")
    args = parser.parse_args()
    if args.url:
        token = os.environ["CLICKHOUSE_MCP_AUTH_TOKEN"]
        client = Client(args.url, auth=token, timeout=60)
    else:
        client = Client(StdioTransport("uv", ["tool", "run", "--python", "3.13", "--from",
                        "mcp-clickhouse==0.6.0", "mcp-clickhouse"], env=connection_env()), timeout=60)
    await check(client)

if __name__ == "__main__":
    asyncio.run(main())
