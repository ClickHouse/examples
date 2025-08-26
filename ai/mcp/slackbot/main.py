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
from pydantic_ai.mcp import MCPServerStdio
import altair as alt
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
clickhouse_server = MCPServerStdio(
    'uv',
    args=[
        'run',
        '--with', 'mcp-clickhouse',
        '--python', '3.13',
        'mcp-clickhouse'
    ],
    env=CLICKHOUSE_ENV,
    timeout=30.0
)

agent = Agent(
    "anthropic:claude-sonnet-4-0",
    mcp_servers=[clickhouse_server],
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
    """Render Vega-Lite spec to PNG and upload to Slack"""
    try:
        # Parse the Vega-Lite specification
        if isinstance(vega_lite_spec, str):
            spec = json.loads(vega_lite_spec)
        else:
            spec = vega_lite_spec
            
        # Render to PNG using vl-convert
        png_data = vlc.vegalite_to_png(spec)
        
        # Create temporary file
        with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as tmp_file:
            tmp_file.write(png_data)
            tmp_file.flush()
            
            # Upload file to Slack
            response = await client.files_upload_v2(
                channel=channel,
                file=tmp_file.name,
                title=title,
                thread_ts=thread_ts
            )
            
        # Clean up temp file
        os.unlink(tmp_file.name)
        return response
        
    except Exception as e:
        logging.error(f"Error rendering and uploading chart: {e}")
        return None

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
            
            # Check if the response contains Vega-Lite chart specifications
            response_text = result.output
            client = AsyncWebClient(token=SLACK_BOT_TOKEN)
            
            # Extract Vega-Lite specifications from the response
            vega_specs = extract_vega_lite_specs(response_text)
            
            if vega_specs:
                # Render and upload each chart found
                for i, spec in enumerate(vega_specs):
                    chart_title = spec.get("title", f"Chart {i+1}" if len(vega_specs) > 1 else "Chart")
                    await render_and_upload_chart(client, channel, thread_ts, spec, chart_title)
                
                # Remove JSON blocks from text response to avoid clutter
                clean_text = re.sub(r'```json\s*\{.*?\}\s*```', '[Chart uploaded above]', response_text, flags=re.DOTALL)
                await say(text=clean_text, thread_ts=thread_ts)
            else:
                await say(text=response_text, thread_ts=thread_ts)

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
