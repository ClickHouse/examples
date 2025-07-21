# Open WebUI and the ClickHouse MCP Server

Open WebUI lets you build LLM-based chat apps.

If you want to run these examples locally, you'll need to first clone the repository:

```
git clone https://github.com/ClickHouse/examples.git
cd examples/ai/mcp/open-webui
```

To launch Open WebUI, you can run the following command:

```bash
uv run --with open-webui open-webui serve
```

Navigate to http://localhost:8080/ to see the UI.

## Configure ClickHouse MCP Server

To setup the ClickHouse MCP Server, we'll need to convert the MCP Server to Open API endpoints.
Let's first set environmental variables that will let us connect to the ClickHouse SQL Playground:

```
export CLICKHOUSE_HOST="sql-clickhouse.clickhouse.com"
export CLICKHOUSE_USER="demo"
export CLICKHOUSE_PASSWORD=""
```

And, then, we can run `mcpo` to create the Open API endpoints: 

```
uvx mcpo --port 8000 -- uv run --with mcp-clickhouse --python 3.10 mcp-clickhouse
```

You can see a list of the endpoints created by navigating to http://localhost:8000/docs

![Open API endpoints](images/0_endpoints.png)

To use these endpoints with Open WebUI, we need to navigate to settings:

![Open WebUI settings](images/1_settings.png)

Click on `Tools`:

![Open WebUI tools](images/2_tools_page.png)

Add http://localhost:8000 as the tool URL:

![Open WebUI tool](images/3_add_tool.png)

Once we've done this, we should see a `1` next to the tool icon on the chat bar:

![Open WebUI tools available](images/4_tools_available.png)

If we click on the tool icon, we can then list the available tools:

![Open WebUI tool listing](images/5_list_of_tools.png)

## Configure OpenAI

By default, Open WebUI works with Ollama models, but we can add OpenAI compatible endpoints as well.
These are configured via the settings menu, but this time we need to click on the `Connections` tab:

![Open WebUI connections](images/6_connections.png)

Let's add the endpoint and our OpenAI key:

![Open WebUI - Add OpenAI as a connection](images/7_add_connection.png)

The OpenAI models will then be available on the top menu:

![Open WebUI - Models](images/8_openai_models.png)

## Chat to ClickHouse MCP Server

We can then have a conversation and Open WebUI will call the MCP Server if necessary:

![Open WebUI - Chat with ClickHouse MCP Server](images/9_conversation.png)