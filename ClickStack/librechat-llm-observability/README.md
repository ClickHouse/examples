# Instrument Librechat and ClickHouse MCP Server using ClickStack

## Deploy ClickStart

The easiest to get ClickStack up and running is to run it locally using docker. You can follow the [documentation](https://clickhouse.com/docs/use-cases/observability/clickstack/getting-started#deploy-stack-with-docker) here to get started.

Once ClickStack is up and running, get the [Ingestion API Key](https://clickhouse.com/docs/use-cases/observability/clickstack/getting-started/sample-data#copy-ingestion-api-key) from the Team settings menu.

## Configure librechat

Librechat requires an access to LLM to work. This demo has been tested only with Anthropic models, but other LLM provider should provide similar experience. 

Rename the file env.example to .env and edit to put your LLM Api key. See librechat [documentation](https://www.librechat.ai/docs/configuration/dotenv#anthropic) for more information.

On top the `.env` file, copy the Ingestion API Key from ClickStack under the value `HYPERDX_API_KEY`. 

## Configure ClickHouse MCP Server

[ClickHouse MCP Server](https://github.com/ClickHouse/mcp-clickhouse) allows LLM to query ClickHouse. 

You need to configure ClickHouse MCP Server to connect to your ClickHouse deployment. 

Edit the following environment variables in the file `.env`:

- `CLICKHOUSE_HOST`: ClickHouse deployment URL
- `CLICKHOUSE_USER`: Clickhouse username
- `CLICKHOUSE_PASSWORD`: Clickhouse password

By default, the environement is configured to connect to the public [ClickHouse SQL Playground](https://sql.clickhouse.com/). 

## Start librechat locally. 

Run `docker compose up` to start librechat.

You can access it at `http://localhost:3080`. 





