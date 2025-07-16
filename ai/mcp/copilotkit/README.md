This is an example of how to build an agentic application using data stored in ClickHouse. It uses the [ClickHouse MCP Server](https://github.com/ClickHouse/mcp-clickhouse) to query data from ClickHouse and generate charts based on the data. 

[CopilotKit](https://github.com/CopilotKit/CopilotKit) is used to build the UI and provide a chat interface to the user.

# Prerequisites

- Node.js >= 20.14.0
- uv >= 0.1.0

# Install dependencies

Clone the project locally: `git clone https://github.com/ClickHouse/examples` and navigate to the `ai/mcp/copilotkit` directory.

Skip this section and run the script `./install.sh` to install dependencies. If you want to install dependencies manually, follow the instructions below.

## Install dependencies manually

1. Install dependencies: 

Run `npm install` to install node dependencies.

2. Install mcp-clickhouse:

Create a new folder `external` and clone the mcp-clickhouse repository into it.

```
mkdir -p external
git clone https://github.com/ClickHouse/mcp-clickhouse external/mcp-clickhouse
```

Install Python dependencies and add fastmcp cli tool.

```
cd external/mcp-clickhouse
uv sync
uv add fastmcp
```

# Configure the application

Copy the `env.example` file to `.env` and edit it to provide your ANTHROPIC_API_KEY. 

## Bring your own LLM

If you'd rather use another LLM provider than Anthropic, you can modify the [Copilotkit runtime](./app/api/copilotkit/route.ts) to use a different LLM adapter. [Here](https://docs.copilotkit.ai/guides/bring-your-own-llm) is a list of supported providers.

## Use your own ClickHouse cluster

By default, the example is configured to connect to the [ClickHouse demo cluster](https://sql.clickhouse.com/). You can also use your own ClickHouse cluster by setting the following environment variables:

- `CLICKHOUSE_HOST`
- `CLICKHOUSE_PORT`
- `CLICKHOUSE_USER`
- `CLICKHOUSE_PASSWORD`
- `CLICKHOUSE_SECURE`

# Run the application

Run `npm run dev` to start the development server.

You can test the Agent using prompt like: "Show me the price evolution in Manchester for the last 10 years.", please note that this is only a demo and a lot of edge cases have not been tested.

Open [http://localhost:3000](http://localhost:3000) with your browser to see the result.
