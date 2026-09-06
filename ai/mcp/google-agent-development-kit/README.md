# Google ADK with ClickHouse MCP

An ADK agent using **google-adk[mcp] 2.8.0** and ClickHouse MCP **0.6.0**. The MCP adapter queried local ClickHouse 26.8.2.7 and the ADK web UI started on 5 September 2026. The live Luna path through LiteLLM passed; Gemini remains unverified; see [validation](../VALIDATION.md).

Use the agent with [ClickHouse Cloud](https://clickhouse.com/cloud), including **$300 credits for a 30-day trial**.


## OpenAI configuration

Set `LLM_PROVIDER=openai`, `OPENAI_MODEL=gpt-5.6-luna`, and `OPENAI_API_KEY` before launching. `OPENAI_BASE_URL` optionally selects an OpenAI-compatible endpoint. The Luna path was tested live against ClickHouse 26.8.2.7. Other provider paths retain their configurable models and are separately unverified.


Follow the [shared setup](../README.md#setup), export `GOOGLE_API_KEY`, and choose the playground, local, or Cloud connection. `GOOGLE_MODEL` defaults to `gemini-3.6-flash`.

From this directory:

```sh
uv run --python 3.13 --with-requirements requirements.txt adk web --port 8091
```

Open http://localhost:8091, select **mcp_agent**, and ask “What tables are available?” With the shared fixture, ask “Calculate revenue by region from mcp_demo.sales.” Expected revenue: North 250, South 500.

For a terminal conversation:

```sh
uv run --python 3.13 --with-requirements requirements.txt adk run mcp_agent
```

The MCP extra is required in ADK 2.8. The agent uses `McpToolset` and starts a pinned stdio server in an isolated uv environment. See [Google ADK MCP tools](https://google.github.io/adk-docs/tools-custom/mcp-tools/).

Stop with Ctrl-C; see [database cleanup](../README.md#cleanup).
