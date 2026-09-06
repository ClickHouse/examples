# LlamaIndex and ClickHouse MCP

Query ClickHouse through an agent built with LlamaIndex. Follow the [shared setup](../README.md#setup) for the public playground, local fixture, or ClickHouse Cloud.

Use your own data with [ClickHouse Cloud](https://clickhouse.com/cloud), including **$300 credits for a 30-day trial**.


## OpenAI configuration

Set `LLM_PROVIDER=openai`, `OPENAI_MODEL=gpt-5.6-luna`, and `OPENAI_API_KEY` before launching. `OPENAI_BASE_URL` optionally selects an OpenAI-compatible endpoint. The Luna path was tested live against ClickHouse 26.8.2.7. Other provider paths retain their configurable models and are separately unverified.


## Run

From this directory, with your provider key and ClickHouse connection exported:

```sh
uv run --python 3.13 --with jupyterlab --with-requirements requirements.txt jupyter lab --notebook-dir .
```

Open [llamaindex.ipynb](llamaindex.ipynb) and run the cells in order. Use `MCP_PROMPT="Use mcp_demo.sales to calculate revenue by region."` for the shared local/Cloud fixture. Expected totals are North 250 and South 500.

## Versions and checks

Selected direct dependencies: llama-index-core==0.14.24; llama-index-llms-anthropic==0.12.0; llama-index-tools-mcp==0.6.0. MCP server: **0.6.0**, Python: **3.13**.

The agent uses FunctionAgent and its asynchronous run method. Temperature is 1 for compatibility with the default Claude model.

The native MCP adapter passed `SELECT 1` against ClickHouse 26.8.2.7. The live Luna fixture query passed.

Stop Jupyter with Ctrl-C and follow [shared cleanup](../README.md#cleanup).
