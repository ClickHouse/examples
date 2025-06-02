# Build a dashboard in Python with ClickHouse and Streamlit

You can run this dashboard with the following command:

```bash
uv run --with streamlit --with clickhouse-connect --with plotly \
streamlit run dashboard.py --server.headless true
```

Then, navigate to http://localhost:8501