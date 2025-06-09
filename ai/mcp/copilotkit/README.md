This is an example of how to build an agentic application using data stored in ClickHouse. It uses MCP to query data from ClickHouse and generate charts based on the data. CopilotKit is used to build the UI and provide a chat interface to the user.

## How to run it

Clone the project locally: `git clone https://github.com/ClickHouse/examples`

Go to the `ai/mcp/copilotkit` directory and run `./install.sh` to install dependencies.

Copy the `env.example` file to `.env` and fill in the environment variables. By default, the example is configured to connect to the [ClickHouse demo cluster](https://sql.clickhouse.com/). You can also use your own ClickHouse cluster by setting the environment variables.

The example also uses Anthropic's API to generate charts based on the data. You can use your own Anthropic API key by setting the environment variable `ANTHROPIC_API_KEY`. If you'd rather use another LLM provider, you can modify the [Copilotkit runtime](./app/api/copilotkit/route.ts) to use a different LLM adapter. 

Run `yarn dev` to start the development server.

Open [http://localhost:3000](http://localhost:3000) with your browser to see the result.

