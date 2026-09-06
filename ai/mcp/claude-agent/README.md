# Claude Agent SDK and ClickHouse MCP

Query ClickHouse through an agent built with Claude Agent SDK. Follow the [shared setup](../README.md#setup) for the public playground, local fixture, or ClickHouse Cloud.

Use your own data with [ClickHouse Cloud](https://clickhouse.com/cloud), including **$300 credits for a 30-day trial**.

## Run

From this directory, with your provider key and ClickHouse connection exported:

```sh
uv run --python 3.13 --with jupyterlab --with-requirements requirements.txt jupyter lab --notebook-dir .
```

Open [claude-agent.ipynb](claude-agent.ipynb) and run the cells in order. Use `MCP_PROMPT="Use mcp_demo.sales to calculate revenue by region."` for the shared local/Cloud fixture. Expected totals are North 250 and South 500.

Alternatively, run the script:

```sh
uv run --python 3.13 agent.py
```

## Versions and checks

Selected direct dependencies: claude-agent-sdk==0.2.152. MCP server: **0.6.0**, Python: **3.13**.

The Claude SDK allowlist names list_databases, list_tables, and run_query. chDB is not used. The SDK also requires its bundled Claude runtime and Anthropic authentication for a conversation.

The native MCP adapter passed `SELECT 1` against ClickHouse 26.8.2.7. Claude model conversations remain unverified: this refresh's paid tests were restricted to OpenAI Luna.

Stop Jupyter with Ctrl-C and follow [shared cleanup](../README.md#cleanup).
