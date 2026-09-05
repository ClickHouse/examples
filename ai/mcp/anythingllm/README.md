# AnythingLLM with ClickHouse MCP

AnythingLLM **1.16.1** and ClickHouse MCP **0.6.0** can use stdio on the desktop or authenticated Streamable HTTP in Docker. The Docker app started and its native MCP client queried ClickHouse on 5 September 2026. The native agent/MCP path passed a live Luna query; Desktop setup and browser interaction remain unverified; see [validation](../VALIDATION.md).

Explore your data with [ClickHouse Cloud](https://console.clickhouse.cloud/signUp), including **$300 credits for a 30-day trial**.

## Docker

Install Docker with Compose. From this directory:

```sh
cp ../.env.example .env
cp anythingllm_mcp_servers.http.json mcp-config.json
```

Generate a token using `openssl rand -hex 32`. Set `CLICKHOUSE_MCP_AUTH_TOKEN` in `.env` and replace `REPLACE_WITH_YOUR_MCP_TOKEN` in `mcp-config.json` with the same value. Both files are ignored by Git. The example uses the public SQL playground; the [shared setup](../README.md#local-clickhouse) explains local and Cloud connections.

```sh
docker compose up -d
```

Open http://localhost:3001, complete onboarding, and configure your LLM provider/key and a model with tool support. Create a workspace, enable the ClickHouse MCP server in the agent settings, and use an `@agent` message such as “What tables are available?” With the shared fixture, ask “Calculate revenue by region from mcp_demo.sales.” Expected revenue: North 250, South 500.

The app uses `type: "streamable"` and the internal URL `http://mcp-clickhouse:8000/mcp`. See [AnythingLLM MCP configuration](https://docs.anythingllm.com/mcp-compatibility/overview).

## Desktop alternative

Install AnythingLLM Desktop and uv. Merge [anythingllm_mcp_servers.json](anythingllm_mcp_servers.json) into the app's MCP configuration through its Agent Skills settings. It launches the pinned server with uv and supplies the playground connection explicitly. If the app cannot find uv, replace `command` with its absolute path. Restart/reload the MCP server after changes.

To use local ClickHouse or Cloud, edit the connection values in the JSON following the shared setup. Desktop and Docker have different network contexts; `localhost` refers to the process running the MCP server.

## Verify and stop

```sh
uv run --env-file .env ../smoke_test.py --url http://127.0.0.1:8001/mcp
docker compose down
```

Use `MCP_PORT=8003 docker compose up -d` if port 8001 is occupied. Volumes retain app data; `docker compose down -v` deletes it. Delete the generated `mcp-config.json` when you no longer need its token.
