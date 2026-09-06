# mcp-agent and ClickHouse MCP

Query ClickHouse through an agent built with mcp-agent. Follow the [shared setup](../README.md#setup) for the public playground, local fixture, or ClickHouse Cloud.

Use your own data with [ClickHouse Cloud](https://clickhouse.com/cloud), including **$300 credits for a 30-day trial**.

## Run

From this directory, with your provider key and ClickHouse connection exported:

```sh
uv run --python 3.13 --with jupyterlab --with-requirements requirements.txt jupyter lab --notebook-dir .
```

Open [mcp-agent.ipynb](mcp-agent.ipynb) and run the cells in order. Use `MCP_PROMPT="Use mcp_demo.sales to calculate revenue by region."` for the shared local/Cloud fixture. Expected totals are North 250 and South 500.

Alternatively, run the script:

```sh
uv run --python 3.13 agent.py
```

## Versions and checks

Selected direct dependencies: mcp-agent==0.2.6; openai==3.8.0; mcp==1.28.1. MCP server: **0.6.0**, Python: **3.13**.

The current mcp-agent release still imports MCP SDK 1.x APIs. Its requirements explicitly pin MCP 1.28.1.

The native MCP adapter passed `SELECT 1` against ClickHouse 26.8.2.7. The live GPT-5.6 Luna fixture query passed.

Stop Jupyter with Ctrl-C and follow [shared cleanup](../README.md#cleanup).
