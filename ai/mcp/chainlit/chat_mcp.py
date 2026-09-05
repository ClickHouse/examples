import json
import os

import anthropic
import chainlit as cl
from mcp import ClientSession
from chainlit.config import config

# Chainlit deliberately passes only a minimal environment to stdio servers.
# Supply the ClickHouse variables explicitly; these stay on the server.
for server in config.features.mcp.servers:
    if server.name == "clickhouse" and server.type == "stdio":
        server.env = {key: os.getenv(key, default) for key, default in {
            "CLICKHOUSE_HOST": "sql-clickhouse.clickhouse.com",
            "CLICKHOUSE_PORT": "8443", "CLICKHOUSE_USER": "demo",
            "CLICKHOUSE_PASSWORD": "", "CLICKHOUSE_SECURE": "true",
        }.items()}


client = None

@cl.on_chat_start
async def start_chat():
    cl.user_session.set("chat_messages", [])

@cl.on_mcp_connect
async def on_mcp(connection, session: ClientSession):
    result = await session.list_tools()
    connections = cl.user_session.get("mcp_tools", {})
    connections[connection.name] = [
        {"name": t.name, "description": t.description, "input_schema": t.inputSchema}
        for t in result.tools
    ]
    cl.user_session.set("mcp_tools", connections)

@cl.on_mcp_disconnect
async def on_mcp_disconnect(name, session):
    connections = cl.user_session.get("mcp_tools", {})
    connections.pop(name, None)
    cl.user_session.set("mcp_tools", connections)

@cl.step(type="tool")
async def call_tool(tool_use):
    step = cl.context.current_step
    step.name = tool_use.name
    connections = cl.user_session.get("mcp_tools", {})
    name = next((name for name, tools in connections.items()
                 if any(t["name"] == tool_use.name for t in tools)), None)
    connection = cl.context.session.mcp_sessions.get(name) if name else None
    if not connection:
        result = {"content": "MCP connection is unavailable.", "is_error": True}
    else:
        try:
            response = await connection[0].call_tool(tool_use.name, tool_use.input)
            text = "\n".join(block.text for block in response.content if block.type == "text")
            result = {"content": text, "is_error": bool(response.isError)}
        except Exception as exc:
            result = {"content": str(exc), "is_error": True}
    step.output = result["content"]
    return {"type": "tool_result", "tool_use_id": tool_use.id, **result}

async def call_claude(messages):
    global client
    if client is None:
        client = anthropic.AsyncAnthropic()
    message = cl.Message(content="")
    tools = [tool for group in cl.user_session.get("mcp_tools", {}).values() for tool in group]
    async with client.messages.stream(
        model=os.getenv("ANTHROPIC_MODEL", "claude-sonnet-5"),
        max_tokens=4096, messages=messages, **({"tools": tools} if tools else {}),
    ) as stream:
        async for text in stream.text_stream:
            await message.stream_token(text)
        response = await stream.get_final_message()
    if message.content:
        await message.send()
    return response

@cl.on_message
async def on_message(message: cl.Message):
    messages = cl.user_session.get("chat_messages", [])
    messages.append({"role": "user", "content": message.content})
    for _ in range(20):
        response = await call_claude(messages)
        # Preserve every block, including signed thinking blocks and parallel tool calls.
        messages.append({"role": "assistant", "content": [block.model_dump(exclude_none=True) for block in response.content]})
        calls = [block for block in response.content if block.type == "tool_use"]
        if not calls:
            break
        results = [await call_tool(call) for call in calls]
        messages.append({"role": "user", "content": results})
    else:
        await cl.Message(content="Stopped after 20 tool rounds. Try a more specific question.").send()
    cl.user_session.set("chat_messages", messages)
