# Google Agent Development Kit and the ClickHouse MCP Server


```
git clone https://github.com/ClickHouse/examples.git
cd examples/ai/mcp/google-agent-development-kit
```

Copy the `.env.example` file to `.env` in the `mcp_agent` directory:

```
cp mcp_agent/.env.example mcp_agent/.env
```

Edit the `.env` file to include your [Google AI API key](https://aistudio.google.com/).

Run the agent using the Agent Development Kit Web UI:

```
uv run --with google-adk adk web
```

Navigate to http://localhost:8000/ to access the Agent Development Kit Web UI.
You should something like the following:

![Google ADK UI](images/adk-ui.png)

Alternatively, you can run the agent via the experimental CLI tool:

```
uv run --with google-adk adk run mcp_agent
```

```text
/Users/markhneedham/.cache/uv/archive-v0/0-5wnAW-k958IQqO67xh4/lib/python3.12/site-packages/google/adk/cli/cli.py:154: UserWarning: [EXPERIMENTAL] InMemoryCredentialService: This feature is experimental and may change or be removed in future versions without notice. It may introduce breaking changes at any time.

[user]: What tables can we query?
[database_agent]: Could you please specify the database you're interested in?
[user]: What databases are there?
2025-10-06 11:09:17,264 - mcp.server.lowlevel.server - INFO - Processing request of type ListToolsRequest
2025-10-06 11:09:17,806 - mcp.server.lowlevel.server - INFO - Processing request of type CallToolRequest
2025-10-06 11:09:17,809 - mcp-clickhouse - INFO - Listing all databases
2025-10-06 11:09:17,809 - mcp-clickhouse - INFO - Creating ClickHouse client connection to sql-clickhouse.clickhouse.com:8443 as demo (secure=True, verify=True, connect_timeout=30s, send_receive_timeout=30s)
2025-10-06 11:09:18,512 - mcp-clickhouse - INFO - Successfully connected to ClickHouse server version 25.8.1.8344
2025-10-06 11:09:18,718 - mcp-clickhouse - INFO - Found 38 databases
2025-10-06 11:09:18,728 - mcp.server.lowlevel.server - INFO - Processing request of type ListToolsRequest
[database_agent]: Here are the databases you can query: "amazon", "bluesky", "country", "covid", "default", "dns", "environmental", "forex", "geo", "git", "github", "hackernews", "imdb", "logs", "metrica", "mgbench", "mta", "noaa", "nyc_taxi", "nypd", "ontime", "otel", "otel_clickpy", "otel_json", "otel_v2", "pypi", "random", "rubygems", "stackoverflow", "star_schema", "stock", "system", "tw_weather", "twitter", "uk", "wiki", "words", "youtube".
```