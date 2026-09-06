# Chainlit with ClickHouse MCP

A streaming chat app using **Chainlit 2.12.0** and **ClickHouse MCP 0.6.0**. The OpenAI entry point passed a live GPT-5.6 Luna query, follow-up, and failed-SQL check on 5 September 2026. Anthropic's tool loop passed offline regressions. Browser interaction remains unverified; see [validation](../VALIDATION.md).

Query your own data with [ClickHouse Cloud](https://clickhouse.com/cloud), including **$300 credits for a 30-day trial**.

## Run with OpenAI

Follow the [shared setup](../README.md#setup), export `OPENAI_API_KEY` and your ClickHouse connection, then run from this directory:

```sh
uv run --python 3.13 --with-requirements requirements.txt chainlit run chat_openai.py --port 8090
```

Open http://localhost:8090. In the MCP menu, connect **clickhouse**. Ask “What tables can you query?” With the shared local/Cloud fixture, ask “Calculate revenue by region from mcp_demo.sales.” Expected revenue: North 250, South 500.

`OPENAI_MODEL` defaults to `gpt-5.6-luna`. The app streams text and tool arguments, keeps conversation history, and returns query errors to the model.

Chainlit 2.12 uses server entries in [.chainlit/config.toml](.chainlit/config.toml). The shared connection hooks in `chat_mcp.py` pass ClickHouse environment variables explicitly to the pinned subprocess. Users select the named server. See [Chainlit MCP documentation](https://docs.chainlit.io/advanced-features/mcp).

## Anthropic alternatives

Export `ANTHROPIC_API_KEY`, then run `chat_mcp.py` for the Anthropic MCP example or `chat_basic.py` for chat without database tools:

```sh
uv run --python 3.13 --with-requirements requirements.txt chainlit run chat_mcp.py --port 8090
```

`ANTHROPIC_MODEL` defaults to `claude-sonnet-5`. These model calls were not included in the Luna-only live validation. MCP SDK 1.28.1 is pinned because Chainlit requires SDK 1.x; the MCP server runs in its own environment.

## Offline checks and cleanup

```sh
uv run --python 3.13 --with-requirements requirements.txt ../tests/app_smoke.py chainlit
```

Stop the app with Ctrl-C; see [database cleanup](../README.md#cleanup).
