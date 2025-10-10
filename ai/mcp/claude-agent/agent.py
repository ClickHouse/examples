# /// script
# requires-python = ">=3.9"
# dependencies = [
#   "claude-agent-sdk",
# ]
# ///


import asyncio
from claude_agent_sdk import query, ClaudeAgentOptions, AssistantMessage, UserMessage, TextBlock, ToolUseBlock

env = {
    "CLICKHOUSE_HOST": "sql-clickhouse.clickhouse.com",
    "CLICKHOUSE_PORT": "8443", 
    "CLICKHOUSE_USER": "demo",
    "CLICKHOUSE_PASSWORD": "",
    "CLICKHOUSE_SECURE": "true",
    "CLICKHOUSE_VERIFY": "true",
    "CLICKHOUSE_CONNECT_TIMEOUT": "30",
    "CLICKHOUSE_SEND_RECEIVE_TIMEOUT": "30"
}

options = ClaudeAgentOptions(
    allowed_tools=[
        "mcp__mcp-clickhouse__list_databases",
        "mcp__mcp-clickhouse__list_tables", 
        "mcp__mcp-clickhouse__run_select_query",
        "mcp__mcp-clickhouse__run_chdb_select_query"
    ],
    mcp_servers={
        "mcp-clickhouse": {
            "command": "uv",
            "args": [
                "run",
                "--with", "mcp-clickhouse",
                "--python", "3.10",
                "mcp-clickhouse"
            ],
            "env": env
        }
    }
)


async def main():
    async for message in query(prompt="Tell me something interesting about UK property sales", options=options):
        if isinstance(message, AssistantMessage):
            for block in message.content:
                if isinstance(block, TextBlock):
                    print(f"🤖 {block.text}")
                if isinstance(block, ToolUseBlock):
                    print(f"🛠️ {block.name} {block.input}")
        elif isinstance(message, UserMessage):
            for block in message.content:
                if isinstance(block, TextBlock):
                    print(block.text)


asyncio.run(main())