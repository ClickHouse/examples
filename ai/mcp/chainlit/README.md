# Chainlit and the ClickHouse MCP Server

Chainlit lets you build LLM-based chat apps.

We're going to explore it using Anthropic, so you'll need to have you Anthropic API key configured:

```
export ANTHROPIC_API_KEY='sk-xxx'
```

## Basic Chainlit app

You can see an example of a basic chat app by running the following:

```
uv run --with anthropic --with chainlit chainlit run chat_basic.py -w -h
```

Then navigate to http://localhost:8000

## Adding ClickHouse MCP Server

Things get more interesting if we add the ClickHouse MCP Server.
You'll need to update your `.chainlit/config.toml` file to allow the `uv` command to be used:

```toml
[features.mcp.stdio]
    enabled = true
    # Only the executables in the allow list can be used for MCP stdio server.
    # Only need the base name of the executable, e.g. "npx", not "/usr/bin/npx".
    # Please don't comment this line for now, we need it to parse the executable name.
    allowed_executables = [ "npx", "uvx", "uv" ]
```

There's some glue code to get MCP Servers working with Chainlit, so we'll need to run this command to launch Chainlit instead:

```
uv run --with anthropic --with chainlit chainlit run chat_mcp.py -w -h
```

To add the MCP Server, click on the plug icon in the chat interface, and then add the following command to connect to use the ClickHouse SQL Playground:

```
CLICKHOUSE_HOST=sql-clickhouse.clickhouse.com CLICKHOUSE_USER=demo CLICKHOUSE_PASSWORD= CLICKHOUSE_SECURE=true uv run --with mcp-clickhouse --python 3.13 mcp-clickhouse
```

If you want to use your own ClickHouse instance, you can adjust the values of the environment variables.

You can then ask it questions like this:

* Tell me about the tables that you have to query
* What's something interesting about New York taxis?