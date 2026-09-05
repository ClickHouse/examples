"""OpenAI chat with the same configured ClickHouse MCP connection."""
import json
import os
from types import SimpleNamespace

import chainlit as cl
from openai import AsyncOpenAI
# Import the shared connection hooks, configuration, and tool step.
from chat_mcp import call_tool, on_mcp, on_mcp_disconnect, start_chat

async def call_openai(messages):
    definitions = [
        {"type": "function", "function": {
            "name": tool["name"], "description": tool["description"],
            "parameters": tool["input_schema"],
        }}
        for group in cl.user_session.get("mcp_tools", {}).values() for tool in group
    ]
    message = cl.Message(content="")
    calls = {}
    async with AsyncOpenAI() as client:
        stream = await client.chat.completions.create(
            model=os.getenv("OPENAI_MODEL", "gpt-5.6-luna"), messages=messages,
            max_completion_tokens=1024, stream=True,
            **({"tools": definitions} if definitions else {}),
        )
        async for event in stream:
            if not event.choices:
                continue
            delta = event.choices[0].delta
            if delta.content:
                await message.stream_token(delta.content)
            for call in delta.tool_calls or []:
                entry = calls.setdefault(call.index, {
                    "id": "", "type": "function", "function": {"name": "", "arguments": ""}
                })
                if call.id:
                    entry["id"] = call.id
                if call.function:
                    if call.function.name:
                        entry["function"]["name"] += call.function.name
                    if call.function.arguments:
                        entry["function"]["arguments"] += call.function.arguments
    if message.content:
        await message.send()
    response = {"role": "assistant", "content": message.content or None}
    if calls:
        response["tool_calls"] = [calls[index] for index in sorted(calls)]
    return response

@cl.on_message
async def on_message(message: cl.Message):
    messages = cl.user_session.get("chat_messages", [])
    messages.append({"role": "user", "content": message.content})
    for _ in range(10):
        response = await call_openai(messages)
        messages.append(response)
        calls = response.get("tool_calls", [])
        if not calls:
            break
        for call in calls:
            try:
                arguments = json.loads(call["function"]["arguments"])
                result = await call_tool(SimpleNamespace(
                    id=call["id"], name=call["function"]["name"], input=arguments,
                ))
                content = (json.dumps({"error": result["content"]})
                           if result["is_error"] else result["content"])
            except (ValueError, TypeError) as exc:
                content = json.dumps({"error": str(exc)})
            messages.append({"role": "tool", "tool_call_id": call["id"], "content": content})
    else:
        await cl.Message(content="Stopped after 10 tool rounds. Try a more specific question.").send()
    cl.user_session.set("chat_messages", messages)
