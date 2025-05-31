# Streamlit ClickHouse MCP server example

This app uses Claude Sonnet, so you'll need to set `ANTHROPIC_API_KEY` before launching anything.

To run the Streamlit app:

```
uv run \
  --with streamlit \
  --with agno \
  --with anthropic \
  --with mcp \
  streamlit run app.py --server.headless true
```

You can then navigate to http://localhost:8501