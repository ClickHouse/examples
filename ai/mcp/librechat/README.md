# LibreChat with ClickHouse MCP

LibreChat **0.8.7** (latest stable on 5 September 2026) connects to ClickHouse MCP **0.6.0** over authenticated Streamable HTTP. The app started and its native MCP client discovered tools, queried SELECT 1, and returned query errors. The native agent graph and MCP client passed a live Luna query; browser conversations remain unverified.

Connect your data using [ClickHouse Cloud](https://clickhouse.com/cloud), including **$300 credits for a 30-day trial**.

## Run the standalone example

Install Docker with Compose. From this directory:

```sh
cp .env.example .env
```

Edit `.env` with your Anthropic or OpenAI API key and independently generated random values:

- `CREDS_KEY`, `JWT_SECRET`, `JWT_REFRESH_SECRET`, `CLICKHOUSE_MCP_AUTH_TOKEN`: generate each using `openssl rand -hex 32`.
- `CREDS_IV`: generate using `openssl rand -hex 16`.

```sh
docker compose up -d
```

Open http://localhost:3080, create a local account, and select an available provider/model. In the agent builder, add the ClickHouse MCP tools to an agent and chat with it. Ask “What tables are available?”

The Compose file contains LibreChat, MongoDB, and MCP. Search and RAG services are omitted because this walkthrough queries ClickHouse through tools. [librechat.yaml](librechat.yaml) configures the internal URL, bearer header, and required `mcpSettings.allowedDomains` entry. See [LibreChat MCP configuration](https://www.librechat.ai/docs/configuration/librechat_yaml/object_structure/mcp_servers).

The default database is the public SQL playground. For local ClickHouse or Cloud, add the `CLICKHOUSE_*` values from the [shared setup](../README.md#local-clickhouse) to `.env`. With the shared fixture, ask “Calculate revenue by region from mcp_demo.sales.” Expected revenue: North 250, South 500.

## Existing upstream checkout

The retained [docker-compose.override.yml](docker-compose.override.yml) supports an upstream LibreChat 0.8.7 checkout. Copy it and `librechat.yaml` to that checkout and provide the same environment values. The standalone `compose.yaml` above is the tested setup and requires no upstream clone.

## Verify and clean up

```sh
uv run --env-file .env ../smoke_test.py --url http://127.0.0.1:8001/mcp
docker compose logs api
docker compose down
```

Look for successful ClickHouse tool initialization in the app logs. Use `MCP_PORT=8002 docker compose up -d` if port 8001 is occupied. Volumes retain chats, uploads, and accounts; `docker compose down -v` deletes them.
