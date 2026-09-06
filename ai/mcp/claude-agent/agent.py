# /// script
# requires-python = ">=3.13"
# dependencies = [
#   "claude-agent-sdk==0.2.152",
# ]
# ///

import os


import asyncio
from claude_agent_sdk import query, ClaudeAgentOptions, AssistantMessage, UserMessage, TextBlock, ToolUseBlock

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

options = ClaudeAgentOptions(
    model=os.getenv("ANTHROPIC_MODEL", "claude-sonnet-5"),
    allowed_tools=[
        "mcp__mcp-clickhouse__list_databases",
        "mcp__mcp-clickhouse__list_tables",
        "mcp__mcp-clickhouse__run_query"
    ],
    mcp_servers={
        "mcp-clickhouse": {
            "command": "uv",
            "args": ["tool", "run", "--python", "3.13", "--from", "mcp-clickhouse==0.6.0", "mcp-clickhouse"],
            "env": env
        }
    }
)


async def main():
    async for message in query(prompt=os.getenv("MCP_PROMPT", "Tell me something interesting about UK property sales"), options=options):
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


if __name__ == "__main__":
    asyncio.run(main())
