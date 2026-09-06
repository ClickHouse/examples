# Streamlit with ClickHouse MCP

A chat app using Streamlit **1.63.0**, Agno **3.0.6**, and ClickHouse MCP **0.6.0**. Startup, Streamlit's app test, the Agno MCP adapter, and stream-failure regression checks passed on 5 September 2026. The live Luna fixture query and Streamlit AppTest passed; browser rendering remains unverified.

Analyze your own data with [ClickHouse Cloud](https://clickhouse.com/cloud), including **$300 credits for a 30-day trial**.


## OpenAI configuration

Set `LLM_PROVIDER=openai`, `OPENAI_MODEL=gpt-5.6-luna`, and `OPENAI_API_KEY` before launching. `OPENAI_BASE_URL` optionally selects an OpenAI-compatible endpoint. The Luna path was tested live against ClickHouse 26.8.2.7. Other provider paths retain their configurable models and are separately unverified.


Follow the [shared setup](../README.md#setup) to export your selected provider key and the ClickHouse connection. From this directory:

```sh
uv run --python 3.13 --with-requirements requirements.txt streamlit run app.py
```

Open http://localhost:8501. Ask “What tables are available?” For the shared local/Cloud fixture, ask “Calculate revenue by region from mcp_demo.sales.” Expected revenue: North 250, South 500.

The app uses `ANTHROPIC_MODEL` (default `claude-sonnet-5`), passes the conversation history to Agno, and streams its current `RunContentEvent` events. **New chat** clears this session's history. A failed MCP/model stream produces an error in the UI.

Run the failure regression without a model key:

```sh
uv run --python 3.13 --with-requirements requirements.txt ../tests/app_smoke.py streamlit
```

Stop with Ctrl-C; see [database cleanup](../README.md#cleanup).
