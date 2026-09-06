# CrewAI and ClickHouse MCP

Query ClickHouse through an agent built with CrewAI. Follow the [shared setup](../README.md#setup) for the public playground, local fixture, or ClickHouse Cloud.

Use your own data with [ClickHouse Cloud](https://clickhouse.com/cloud), including **$300 credits for a 30-day trial**.

## Run

From this directory, with your provider key and ClickHouse connection exported:

```sh
uv run --python 3.13 --with jupyterlab --with-requirements requirements.txt jupyter lab --notebook-dir .
```

Open [crewai.ipynb](crewai.ipynb) and run the cells in order. Use `MCP_PROMPT="Use mcp_demo.sales to calculate revenue by region."` for the shared local/Cloud fixture. Expected totals are North 250 and South 500.

Alternatively, run the script:

```sh
uv run --python 3.13 agent.py
```

## Versions and checks

Selected direct dependencies: crewai-tools[mcp]==1.15.20. MCP server: **0.6.0**, Python: **3.13**.

Model IDs and ClickHouse credentials can be overridden through environment variables.

The native MCP adapter passed `SELECT 1` against ClickHouse 26.8.2.7. The live GPT-5.6 Luna fixture query passed. See [validation](../VALIDATION.md) for the exact scope.

Stop Jupyter with Ctrl-C and follow [shared cleanup](../README.md#cleanup).
