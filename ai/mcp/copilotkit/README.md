# CopilotKit analytics dashboard with ClickHouse MCP

A dashboard using **CopilotKit 1.70.1**, **Next.js 16.3.4**, **React 19.2.8**, and ClickHouse MCP **0.6.0**. The v2 agent calls MCP tools on the server and a frontend tool adds charts. Production build, lint, runtime startup, and MCP discovery/query/error checks passed on 5 September 2026. The live Luna runtime queried the fixture and emitted correct chart-tool arguments; browser rendering remains unverified; see [validation](../VALIDATION.md).

Build this with your data in [ClickHouse Cloud](https://console.clickhouse.cloud/signUp), including **$300 credits for a 30-day trial**.


## OpenAI configuration

Set `LLM_PROVIDER=openai`, `OPENAI_MODEL=gpt-5.6-luna`, and `OPENAI_API_KEY` before launching. Put these in `.env.local`. `OPENAI_BASE_URL` optionally selects an OpenAI-compatible endpoint. The Luna path was tested live against ClickHouse 26.8.2.7. Other provider paths retain their configurable models and are separately unverified.


## Setup

Install **Node.js 24 LTS** and [uv](https://docs.astral.sh/uv/getting-started/installation/). From this directory:

```sh
./install.sh
cp env.example .env.local
```

Edit `.env.local`: provide `OPENAI_API_KEY` and a random `CLICKHOUSE_MCP_AUTH_TOKEN` generated with `openssl rand -hex 32`. The supplied environment selects `gpt-5.6-luna`. For Anthropic, set `LLM_PROVIDER=anthropic` and provide `ANTHROPIC_API_KEY` / `ANTHROPIC_MODEL`.

The defaults query the public playground. For your own database, use the connection values and shared fixture in the [local/Cloud setup](../README.md#local-clickhouse). Keep the values in `.env.local`. `MCP_ENDPOINT` and the token are server settings.

## Run

```sh
npm run dev
```

This starts Next.js and a pinned MCP server on `127.0.0.1:8000`. Open http://localhost:3000 and ask “Show a chart of Manchester property prices by year for the last ten years.” With the shared fixture, ask “Create a bar chart of revenue by region from mcp_demo.sales.” Expected revenue: North 250, South 500.

The runtime uses CopilotKit's current `BuiltInAgent` with native MCP configuration. The dashboard registers a typed chart tool through the v2 React API. See [CopilotKit MCP servers](https://docs.copilotkit.ai/mcp-servers).

To use an existing HTTP MCP server, set `MCP_ENDPOINT` and its bearer token, then run `npm run dev:next` instead. It must expose Streamable HTTP at `/mcp`.

## Validate and stop

```sh
npm run lint
npm run build
npm run test:mcp
```

The MCP test requires the server to be running; it does not need an Anthropic key. To run the production build, use `npm start` and start MCP separately with `npm run dev:mcp`.

All CopilotKit packages are aligned. TypeScript **6.0.3** and ESLint **9.39.5** are the newest compatible versions tested: TypeScript 7 and ESLint 10 broke the current lint plugins. Remaining upstream dependency advisories are recorded in [validation](../VALIDATION.md).

Stop development processes with Ctrl-C; see [database cleanup](../README.md#cleanup).

Companion article: [Building an agentic application with ClickHouse MCP and CopilotKit](https://clickhouse.com/blog/building-an-agentic-application-with-clickhouse-mcp-server-and-copilotkit). Its v1/SSE setup needs the [listed corrections](../CONTENT_UPDATES.md).
