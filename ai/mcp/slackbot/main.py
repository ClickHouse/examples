import os
import logging
import asyncio

from dotenv import load_dotenv
from slack_bolt.async_app import AsyncApp
from slack_bolt.adapter.socket_mode.aiohttp import AsyncSocketModeHandler
from slack_sdk.web.async_client import AsyncWebClient
from pydantic_ai import Agent
from pydantic_ai.mcp import MCPServerStdio

# Load environment variables from .env file
load_dotenv()

# --- CONFIGURATION ---
SLACK_BOT_TOKEN = os.environ.get("SLACK_BOT_TOKEN", "xoxb-your-token")
SLACK_APP_TOKEN = os.environ.get("SLACK_APP_TOKEN", "xapp-your-app-token")
ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY", "sk-ant-xxx")

# ClickHouse MCP env
CLICKHOUSE_ENV = {
    "CLICKHOUSE_HOST": os.environ.get("CLICKHOUSE_HOST", "sql-clickhouse.clickhouse.com"),
    "CLICKHOUSE_PORT": os.environ.get("CLICKHOUSE_PORT", "8443"),
    "CLICKHOUSE_USER": os.environ.get("CLICKHOUSE_USER", "demo"),
    "CLICKHOUSE_PASSWORD": os.environ.get("CLICKHOUSE_PASSWORD", ""),
    "CLICKHOUSE_SECURE": os.environ.get("CLICKHOUSE_SECURE", "true"),
}

# --- LOGGING ---
logging.basicConfig(level=logging.INFO)

# --- MCP SERVER AND AGENT SETUP ---
mcp_server = MCPServerStdio(
    'uv',
    args=[
        'run',
        '--with', 'mcp-clickhouse',
        '--python', '3.13',
        'mcp-clickhouse'
    ],
    env=CLICKHOUSE_ENV
)

agent = Agent(
    "anthropic:claude-sonnet-4-0",
    mcp_servers=[mcp_server],
    system_prompt="You are a data assistant. You have access to a ClickHouse database from which you can answer the user's questions. You have tools available to you that let you explore the database, e.g. to list available databases, tables, etc., and to execute SQL queries against them. Use these tools to answer the user's questions. You must always answer the user's questions by using the available tools. If the database cannot help you, say so. You must include a summary of how you came to your answer: e.g. which data you used and how you queried it."
)

app = AsyncApp(token=SLACK_BOT_TOKEN)

async def handle_slack_query(event, say):
    user = event["user"]
    text = event.get("text", "")
    thread_ts = event.get("thread_ts") or event["ts"]
    channel = event["channel"]

    await say(text=f"<@{user}>: Let me think...", thread_ts=thread_ts)

    async def do_agent():
        # Build context from thread if present
        context = ""
        if thread_ts and thread_ts != event["ts"]:
            client = AsyncWebClient(token=SLACK_BOT_TOKEN)
            replies = await client.conversations_replies(channel=channel, ts=thread_ts)
            # Exclude the current message, and bot messages
            messages = [m for m in replies["messages"] if m["ts"] != event["ts"]]
            # Format as "user: message"
            context_lines = []
            for m in messages:
                uname = m.get("user", "bot")
                msg = m.get("text", "")
                context_lines.append(f"{uname}: {msg}")
            context = "\n".join(context_lines)

        # Compose prompt for the agent
        if context:
            prompt = f"Thread context so far:\n{context}\n\nNew question: {text}"
        else:
            prompt = text

        async with agent.run_mcp_servers():
            result = await agent.run(prompt)
            await say(text=f"{result.output}", thread_ts=thread_ts)

    asyncio.create_task(do_agent())

@app.event("app_mention")
async def handle_app_mention(event, say):
    await handle_slack_query(event, say)

@app.event("message")
async def handle_dm(event, say):
    if event.get("channel_type") == "im":
        await handle_slack_query(event, say)

async def main():
    handler = AsyncSocketModeHandler(app, SLACK_APP_TOKEN)
    await handler.start_async()

if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
