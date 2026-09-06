# OpenAI Agents SDK with ClickHouse MCP

Examples using **openai-agents 0.22.0**, ClickHouse MCP **0.6.0**, and configurable `OPENAI_MODEL` (default `gpt-5.6-luna`). The MCP adapter and actual SDK span export to ClickHouse passed on 5 September 2026. The live Luna query and trace export passed; the ClickStack UI remains unverified; see [validation](../VALIDATION.md).

Query and trace agents with [ClickHouse Cloud](https://clickhouse.com/cloud), including **$300 credits for a 30-day trial**.

## Query ClickHouse

Follow the [shared setup](../README.md#setup) and export `OPENAI_API_KEY` plus your ClickHouse connection. From this directory:

```sh
uv run --python 3.13 agent_no_tracing.py
```

Alternatively, open [openai-agents.ipynb](openai-agents.ipynb) using the shared notebook instructions. The script disables tracing by default. Set `MCP_PROMPT` to choose a question; with the shared local/Cloud fixture use “Calculate revenue by region from mcp_demo.sales.” Expected revenue: North 250, South 500.

## Export traces to ClickHouse

The trace destination is configured separately from the database the agent queries. Apply [schema.sql](schema.sql) to a writable database. For the local server started from `ai/mcp`:

```sh
cd ..
clickhousectl local client --name mcp-examples --multiquery --queries-file openai-agents/schema.sql
cd openai-agents
export CH_URL=http://localhost:8123
export CH_DB=default
export CH_USER=default
export CH_PASS=
uv run --python 3.13 agent_tracing.py
```

For Cloud, apply the same schema in the SQL console and set `CH_URL=https://YOUR_SERVICE.clickhouse.cloud:8443`, `CH_DB`, `CH_USER`, and `CH_PASS`. The trace writer needs INSERT access to `agent_spans_raw`. The public SQL playground cannot store your traces.

The custom exporter sends acknowledged HTTP inserts and makes background export errors fail the command. It uses the current SDK's span ID and error fields, flushes at shutdown, and exports through this processor only. `agent_tracing_base.py` is the console-export alternative.

Verify the stored spans:

```sql
SELECT TraceId, SpanId, SpanName, Duration, StatusCode, StatusMessage
FROM agent_spans
ORDER BY Timestamp DESC
LIMIT 20;
```

`agent_spans_raw` stores SDK fields. The `agent_spans` view exposes trace-source columns, with **Duration in nanoseconds** and status derived from the span error. To inspect it in ClickStack, configure a trace source for this view and map the corresponding columns. This is a custom SDK tracing example; ClickStack source setup and screenshots have not been retested.

## Model-free validation and cleanup

With local ClickHouse running:

```sh
uv run --python 3.13 --with-requirements requirements.txt ../tests/tracing_smoke.py
```

The test creates an isolated database, exports a successful and a failed SDK span, checks exact duration/status, rejects a malformed timestamp, and removes the test database.

Stop apps with Ctrl-C. Remove `agent_spans` and `agent_spans_raw` only when you no longer need their traces. See [shared cleanup](../README.md#cleanup).

Companion article: [Tracing OpenAI agents with ClickStack](https://clickhouse.com/blog/tracing-openai-agents-clickstack). Its copied exporter/schema instructions need the [listed corrections](../CONTENT_UPDATES.md).
