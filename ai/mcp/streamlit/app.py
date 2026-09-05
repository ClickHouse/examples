import asyncio
import os
import threading
from queue import Queue
from textwrap import dedent

import streamlit as st
from agno.agent import Agent
from agno.models.anthropic import Claude
from agno.models.openai import OpenAIResponses
from agno.run.agent import RunContentEvent
from agno.tools.mcp import MCPTools

from utils import apply_styles

async def stream_clickhouse_agent(messages):
    env = {key: os.getenv(key, default) for key, default in {
        "CLICKHOUSE_HOST": "sql-clickhouse.clickhouse.com",
        "CLICKHOUSE_PORT": "8443", "CLICKHOUSE_USER": "demo",
        "CLICKHOUSE_PASSWORD": "", "CLICKHOUSE_SECURE": "true",
    }.items()}
    async with MCPTools(
        command="uv tool run --python 3.13 --from mcp-clickhouse==0.6.0 mcp-clickhouse",
        env=env, timeout_seconds=60,
    ) as tools:
        agent = Agent(
            model=(OpenAIResponses(id=os.getenv("OPENAI_MODEL", "gpt-5.6-luna"), store=False)
                   if os.getenv("LLM_PROVIDER", "anthropic") == "openai"
                   else Claude(id=os.getenv("ANTHROPIC_MODEL", "claude-sonnet-5"))),
            tools=[tools],
            instructions=dedent("""Use ClickHouse tools to answer questions from data.
                Discover the schema before querying. Present concise results in Markdown.
                If a query fails, explain the error or correct the query."""),
            markdown=True,
        )
        async for chunk in agent.arun(messages, stream=True):
            if isinstance(chunk, RunContentEvent) and isinstance(chunk.content, str):
                yield chunk.content

def run_agent_query_sync(messages):
    """Bridge the async agent stream and propagate failures to Streamlit."""
    queue = Queue()
    done = object()

    def run():
        async def produce():
            async for chunk in stream_clickhouse_agent(messages):
                queue.put(chunk)
        try:
            asyncio.run(produce())
        except Exception as exc:
            queue.put(exc)
        finally:
            queue.put(done)

    threading.Thread(target=run, daemon=True).start()
    while True:
        chunk = queue.get()
        if chunk is done:
            return
        if isinstance(chunk, Exception):
            raise chunk
        yield chunk

st.title("A ClickHouse-backed AI agent")
apply_styles()
if st.button("New chat"):
    st.session_state.messages = []
    st.rerun()
if "messages" not in st.session_state:
    st.session_state.messages = []
for message in st.session_state.messages:
    with st.chat_message(message["role"]):
        st.markdown(message["content"])
if prompt := st.chat_input("Ask a question about your data"):
    st.session_state.messages.append({"role": "user", "content": prompt})
    with st.chat_message("user"):
        st.markdown(prompt)
    with st.chat_message("assistant"):
        try:
            response = st.write_stream(run_agent_query_sync(list(st.session_state.messages)))
        except Exception as exc:
            st.error(str(exc))
        else:
            st.session_state.messages.append({"role": "assistant", "content": response})
