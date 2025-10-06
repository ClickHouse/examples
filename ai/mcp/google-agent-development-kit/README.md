# Google Agent Development Kit and the ClickHouse MCP Server

Google Agent Development Kit (ADK) is a framework for developing and deploying AI agents.

```bash
git clone https://github.com/ClickHouse/examples.git
cd examples/ai/mcp/google-agent-development-kit
```

Copy the `.env.example` file to `.env` in the `mcp_agent` directory:

```bash
cp mcp_agent/.env.example mcp_agent/.env
```

Edit the `.env` file to include your [Google AI API key](https://aistudio.google.com/).

Run the agent using the Agent Development Kit Web UI:

```bash
uv run --with google-adk adk web
```

Navigate to http://localhost:8000/ to access the Agent Development Kit Web UI.
You should something like the following:

![Google ADK UI](images/adk-ui.png)

Alternatively, you can run the agent via the experimental CLI tool:

```bash
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

Finally, we can run the agent via an API endpoint:

```bash
uv run --with google-adk adk api_server
```

We then need to create a session:

```bash
curl -X POST http://localhost:8000/apps/mcp_agent/users/clickhouse_user/sessions/mcp_example
```

```json
{"id":"mcp_example","appName":"mcp_agent","userId":"clickhouse_user","state":{},"events":[],"lastUpdateTime":1759746122.714196}
```

And then we can send a request:

```bash
curl -X POST http://localhost:8000/run \
-H "Content-Type: application/json" \
-d '{
"app_name": "mcp_agent",
"user_id": "clickhouse_user",
"session_id": "mcp_example",
"new_message": {
    "role": "user",
    "parts": [{
    "text": "Hey what was the most expensive property sold in the UK in March 2025?"
    }]
}
}'
```

```json
[
    {"content":{"parts":[{"thoughtSignature":"xxx","functionCall":{"id":"adk-2dc35bef-0730-46a3-9dad-f9e733cf8a89","args":{"query":"SELECT * FROM uk.uk_price_paid WHERE date >= '2025-03-01' AND date < '2025-04-01' ORDER BY price DESC LIMIT 1"},"name":"run_select_query"}}],"role":"model"},"finishReason":"STOP","usageMetadata":{"candidatesTokenCount":63,"promptTokenCount":2097,"promptTokensDetails":[{"modality":"TEXT","tokenCount":2097}],"thoughtsTokenCount":229,"totalTokenCount":2389},"invocationId":"e-a60b0e5f-dfeb-43e8-b65e-d4c73667ca9c","author":"database_agent","actions":{"stateDelta":{},"artifactDelta":{},"requestedAuthConfigs":{},"requestedToolConfirmations":{}},"longRunningToolIds":[],"id":"5755cd59-00a3-4c63-9e9a-b35006263f80","timestamp":1759746221.874846},
    {"content":{"parts":[{"functionResponse":{"id":"adk-2dc35bef-0730-46a3-9dad-f9e733cf8a89","name":"run_select_query","response":{"result":{"content":[{"type":"text","text":"{\"columns\":[\"price\",\"date\",\"postcode1\",\"postcode2\",\"type\",\"is_new\",\"duration\",\"addr1\",\"addr2\",\"street\",\"locality\",\"town\",\"district\",\"county\",\"category\"],\"rows\":[[124519556,\"2025-03-31\",\"WC2E\",\"7PS\",\"other\",0,\"freehold\",\"15\",\"\",\"TAVISTOCK STREET\",\"\",\"LONDON\",\"CITY OF WESTMINSTER\",\"GREATER LONDON\",0]]}"}],"structuredContent":{"columns":["price","date","postcode1","postcode2","type","is_new","duration","addr1","addr2","street","locality","town","district","county","category"],"rows":[[124519556,"2025-03-31","WC2E","7PS","other",0,"freehold","15","","TAVISTOCK STREET","","LONDON","CITY OF WESTMINSTER","GREATER LONDON",0]]},"isError":false}}}}],"role":"user"},"invocationId":"e-a60b0e5f-dfeb-43e8-b65e-d4c73667ca9c","author":"database_agent","actions":{"stateDelta":{},"artifactDelta":{},"requestedAuthConfigs":{},"requestedToolConfirmations":{}},"id":"9376d06f-2597-4869-ab30-17d52ce3d143","timestamp":1759746224.965792},
    {"content":{"parts":[{"text":"The most expensive property sold in the UK in March 2025 was:\n\n*   **Price:** 124,519,556\n*   **Date:** 2025-03-31\n*   **Postcode:** WC2E 7PS\n*   **Address:** 15 TAVISTOCK STREET, LONDON, CITY OF WESTMINSTER, GREATER LONDON\n*   **Type:** Other\n*   **Duration:** Freehold"}],"role":"model"},"finishReason":"STOP","usageMetadata":{"cacheTokensDetails":[{"modality":"TEXT","tokenCount":1590}],"cachedContentTokenCount":1590,"candidatesTokenCount":106,"promptTokenCount":2440,"promptTokensDetails":[{"modality":"TEXT","tokenCount":2440}],"totalTokenCount":2546},"invocationId":"e-a60b0e5f-dfeb-43e8-b65e-d4c73667ca9c","author":"database_agent","actions":{"stateDelta":{},"artifactDelta":{},"requestedAuthConfigs":{},"requestedToolConfirmations":{}},"id":"2aa7454f-1f2a-4ce1-aaa3-91ac705dc5ed","timestamp":1759746224.976058}
]
```