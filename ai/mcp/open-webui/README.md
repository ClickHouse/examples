# Open WebUI with ClickHouse MCP

Open WebUI **0.11.3** connects directly to ClickHouse MCP **0.6.0** using authenticated Streamable HTTP. Container startup and queries through Open WebUI's native MCP client passed on 5 September 2026. The app chat pipeline passed a live Luna query; browser interaction remains unverified; see [validation](../VALIDATION.md).

Use your own data with [ClickHouse Cloud](https://console.clickhouse.cloud/signUp), including **$300 credits for a 30-day trial**.

## Run with Docker Compose

Install Docker with Compose. From this directory:

```sh
cp ../.env.example .env
```

Edit `.env` to set `OPENAI_API_KEY` and a random `CLICKHOUSE_MCP_AUTH_TOKEN` (`openssl rand -hex 32`). The default connection is the public SQL playground. See the [shared local/Cloud instructions](../README.md#local-clickhouse) to use your own database.

```sh
docker compose up -d
```

Open http://localhost:8080 and create the first administrator account. Under **Admin Settings → External Tools**, add a server of type **MCP (Streamable HTTP)**:

- URL: `http://mcp-clickhouse:8000/mcp`
- Authentication: Bearer, using `CLICKHOUSE_MCP_AUTH_TOKEN`
- Name/ID: `clickhouse`

The URL is resolved by the app container. Enable the tool in a chat, select a provider model that supports native tool calling, and use Native function calling. Ask “What tables are available?” With the shared fixture, ask “Calculate revenue by region from mcp_demo.sales.”

See [Open WebUI's native MCP setup](https://docs.openwebui.com/features/extensibility/mcp/). An mcpo/OpenAPI proxy is no longer required for this server.

## Check and clean up

```sh
curl --fail http://localhost:8080/health
uv run --env-file .env ../smoke_test.py --url http://127.0.0.1:8001/mcp
docker compose down
```

MCP's host port defaults to 8001; use `MCP_PORT=8002 docker compose up -d` if another example uses it. Volumes retain accounts and settings. `docker compose down -v` deletes this example's stored app data.
