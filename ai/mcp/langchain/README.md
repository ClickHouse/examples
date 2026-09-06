# LangChain and ClickHouse MCP

Query ClickHouse through an agent built with LangChain. Follow the [shared setup](../README.md#setup) for the public playground, local fixture, or ClickHouse Cloud.

Use your own data with [ClickHouse Cloud](https://clickhouse.com/cloud), including **$300 credits for a 30-day trial**.


## OpenAI configuration

Set `LLM_PROVIDER=openai`, `OPENAI_MODEL=gpt-5.6-luna`, and `OPENAI_API_KEY` before launching. `OPENAI_BASE_URL` optionally selects an OpenAI-compatible endpoint. The Luna path was tested live against ClickHouse 26.8.2.7. Other provider paths retain their configurable models and are separately unverified.


## Run

From this directory, with your provider key and ClickHouse connection exported:

```sh
uv run --python 3.13 --with jupyterlab --with-requirements requirements.txt jupyter lab --notebook-dir .
```

Open [langchain.ipynb](langchain.ipynb) and run the cells in order. Use `MCP_PROMPT="Use mcp_demo.sales to calculate revenue by region."` for the shared local/Cloud fixture. Expected totals are North 250 and South 500.

## Versions and checks

Selected direct dependencies: langchain[mcp,anthropic]==1.4.0; langchain-anthropic==1.7.1. MCP server: **0.6.0**, Python: **3.13**.

This uses LangChain 1.4's built-in MCPAdapter and create_agent. The MCP namespace is currently beta; its API is pinned here.

The native MCP adapter passed `SELECT 1` against ClickHouse 26.8.2.7. The live Luna fixture query passed. See [validation](../VALIDATION.md) for the exact scope.

Stop Jupyter with Ctrl-C and follow [shared cleanup](../README.md#cleanup).
