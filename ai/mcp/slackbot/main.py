import os
import logging
import asyncio
import tempfile
import json
import re

from dotenv import load_dotenv
from slack_bolt.async_app import AsyncApp
from slack_bolt.adapter.socket_mode.aiohttp import AsyncSocketModeHandler
from slack_sdk.web.async_client import AsyncWebClient
from pydantic_ai import Agent
from pydantic_ai.mcp import MCPToolset
from fastmcp import Client
from fastmcp.client.transports import StdioTransport
import vl_convert as vlc

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
clickhouse_server = MCPToolset(Client(StdioTransport(
    "uv", ["tool", "run", "--python", "3.13", "--from", "mcp-clickhouse==0.6.0", "mcp-clickhouse"],
    env=CLICKHOUSE_ENV,
), timeout=60))

agent = Agent(
    ("openai:" + os.getenv("OPENAI_MODEL", "gpt-5.6-luna")
     if os.getenv("LLM_PROVIDER", "anthropic") == "openai"
     else "anthropic:" + os.getenv("ANTHROPIC_MODEL", "claude-sonnet-5")),
    toolsets=[clickhouse_server],
    system_prompt="""You are a data assistant with visualization capabilities. You have access to a ClickHouse database and can create charts from query results.

Available capabilities:
1) ClickHouse tools to explore databases, tables, and execute SQL queries
2) Chart generation by providing Vega-Lite specifications

When users ask for data analysis with visualizations:
1. First query the database using available tools
2. If a visualization would be helpful, create a Vega-Lite chart specification
3. Format your Vega-Lite spec as JSON within ```json blocks
4. Choose appropriate chart types: bar charts for categories, line charts for time series, scatter for correlations, pie for proportions

Example Vega-Lite specification format:
```json
{
  "$schema": "https://vega.github.io/schema/vega-lite/v5.json",
  "title": "Chart Title",
  "data": {"values": [{"category": "A", "value": 100}, {"category": "B", "value": 200}]},
  "mark": "bar",
  "encoding": {
    "x": {"field": "category", "type": "nominal"},
    "y": {"field": "value", "type": "quantitative"}
  }
}
```

Always include a summary of your approach: what data you used, how you queried it, and why you chose a specific visualization."""
)

app = AsyncApp(token=SLACK_BOT_TOKEN)

async def render_and_upload_chart(client, channel, thread_ts, vega_lite_spec, title="Chart"):
    """Render and upload a chart; clean up even when Slack rejects the upload."""
    spec = json.loads(vega_lite_spec) if isinstance(vega_lite_spec, str) else vega_lite_spec
    title = title.strip() if isinstance(title, str) and title.strip() else "Chart"
    png_data = await asyncio.to_thread(vlc.vegalite_to_png, spec)
    with tempfile.TemporaryDirectory(prefix="clickhouse-chart-") as directory:
        filename = os.path.join(directory, "chart.png")
        with open(filename, "wb") as output:
            output.write(png_data)
        return await client.files_upload_v2(
            channel=channel, file=filename, title=title, thread_ts=thread_ts
        )


def extract_vega_lite_specs(text):
    """Extract Vega-Lite JSON specifications from text"""
    # Look for JSON blocks that contain Vega-Lite specs
    json_pattern = r'```json\s*(\{.*?\})\s*```'
    matches = re.findall(json_pattern, text, re.DOTALL)
    
    specs = []
    for match in matches:
        try:
            spec = json.loads(match)
            # Check if it looks like a Vega-Lite spec
            if "$schema" in spec and "vega" in spec["$schema"]:
                specs.append(spec)
        except json.JSONDecodeError:
            continue
    
    return specs

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
            messages = []
            cursor = None
            while True:
                replies = await client.conversations_replies(
                    channel=channel, ts=thread_ts, limit=100, cursor=cursor
                )
                messages.extend(m for m in replies["messages"] if m["ts"] != event["ts"])
                cursor = replies.get("response_metadata", {}).get("next_cursor")
                if not cursor:
                    break
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

        async with agent:
            result = await agent.run(prompt)
            
            # Check if the response contains Vega-Lite chart specifications
            response_text = result.output
            client = AsyncWebClient(token=SLACK_BOT_TOKEN)
            
            # Extract Vega-Lite specifications from the response
            vega_specs = extract_vega_lite_specs(response_text)
            
            if vega_specs:
                logging.info(f"📊 Found {len(vega_specs)} Vega-Lite chart specification(s)")
                
                # Render and upload each chart found
                for i, spec in enumerate(vega_specs):
                    # Log the Vega-Lite spec to console
                    logging.info(f"🎨 Vega-Lite Spec #{i+1}:")
                    logging.info(json.dumps(spec, indent=2))
                    
                    # Ensure we have a valid string title
                    chart_title = spec.get("title") or (f"Chart {i+1}" if len(vega_specs) > 1 else "Chart")
                    if not isinstance(chart_title, str) or not chart_title.strip():
                        chart_title = f"Chart {i+1}" if len(vega_specs) > 1 else "Chart"
                    await render_and_upload_chart(client, channel, thread_ts, spec, chart_title)
                
                # Remove JSON blocks from text response to avoid clutter
                clean_text = re.sub(r'```json\s*\{.*?\}\s*```', '[Chart uploaded above]', response_text, flags=re.DOTALL)
                await say(text=clean_text, thread_ts=thread_ts)
            else:
                await say(text=response_text, thread_ts=thread_ts)

    try:
        await do_agent()
    except Exception:
        logging.exception("Agent query failed")
        await say(text="The query failed. Check the application logs and try again.", thread_ts=thread_ts)

@app.event("assistant_thread_started")
async def handle_assistant_thread_started_events(body, logger):
    logger.info("🤖 Assistant thread started - ignoring event to avoid unnecessary LLM calls")
    logger.info(body)

@app.event("app_mention")
async def handle_app_mention(event, say):
    if not event.get("bot_id") and not event.get("subtype"):
        await handle_slack_query(event, say)

@app.event("message")
async def handle_dm(event, say):
    if event.get("channel_type") == "im" and not event.get("bot_id") and not event.get("subtype"):
        await handle_slack_query(event, say)

async def main():
    handler = AsyncSocketModeHandler(app, SLACK_APP_TOKEN)
    await handler.start_async()

if __name__ == "__main__":
    asyncio.run(main())
