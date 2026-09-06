# ClickHouse MCP examples

Connect an agent framework or chat app to [ClickHouse MCP](https://github.com/ClickHouse/mcp-clickhouse). These examples use **MCP server 0.6.0**, Python **3.13**, and configurable model IDs. Framework dependencies were refreshed on **5 September 2026**. 18 integrations have passed live OpenAI/MCP checks with GPT-5.6 Luna; see [PR #407](https://github.com/ClickHouse/examples/pull/407) for the scope and limitations. Claude Agent SDK and browser walkthroughs remain unverified.

Use your own data with [ClickHouse Cloud](https://clickhouse.com/cloud), including **$300 credits for a 30-day trial**. The examples also support the public SQL playground and local ClickHouse.

## Choose an example

Each Python framework has its own requirements file. Use separate environments: some current frameworks still require MCP SDK 1.x, while others use 2.x. Both communicate with the separately launched MCP server 0.6.0.

| Example | Framework version | Interface |
| --- | --- | --- |
| [Agno](agno/) | 3.0.6 | Notebook |
| [Claude Agent SDK](claude-agent/) | 0.2.152 | Notebook, script |
| [CrewAI](crewai/) | 1.15.20 | Notebook, script |
| [DSPy](dspy/) | 3.3.1 | Notebook |
| [Google ADK](google-agent-development-kit/) | 2.8.0 | Web UI, CLI, API |
| [LangChain](langchain/) | 1.4.0 | Notebook |
| [LlamaIndex](llamaindex/) | Core 0.14.24 | Notebook |
| [mcp-agent](mcp-agent/) | 0.2.6 | Notebook, script |
| [Microsoft Agent Framework](microsoft-agent-framework/) | 1.17.0 | Notebook |
| [OpenAI Agents SDK](openai-agents/) | 0.22.0 | Notebook, scripts, tracing |
| [PydanticAI](pydanticai/) | 2.40.0 | Notebook |
| [Upsonic](upsonic/) | 0.77.3 | Notebook, script |
| [Chainlit](chainlit/) | 2.12.0 | Chat app |
| [Streamlit](streamlit/) | 1.63.0, Agno 3.0.6 | Chat app |
| [Slackbot](slackbot/) | Slack Bolt 1.30.0, PydanticAI 2.40.0 | Slack |
| [CopilotKit](copilotkit/) | 1.70.1, Next.js 16.3.4 | Analytics dashboard |
| [LibreChat](librechat/) | 0.8.7 (latest stable) | Docker chat app |
| [Open WebUI](open-webui/) | 0.11.3 | Docker chat app |
| [AnythingLLM](anythingllm/) | 1.16.1 | Desktop or Docker |

## Setup

Install [uv](https://docs.astral.sh/uv/getting-started/installation/), then clone this repository:

```sh
git clone https://github.com/ClickHouse/examples.git
cd examples/ai/mcp
cp .env.example .env
```

Edit `.env` with your model provider key. It selects `LLM_PROVIDER=openai` and `OPENAI_MODEL=gpt-5.6-luna` for generic examples. Claude Agent SDK requires an Anthropic key; use Chainlit's `chat_openai.py` for OpenAI. `ANTHROPIC_MODEL`, `OPENAI_MODEL`, and `GOOGLE_MODEL` override the defaults. Export the variables before launching scripts or notebooks:

```sh
set -a
. ./.env
set +a
```

The default connection is the read-only [SQL playground](https://sql.clickhouse.com/). No ClickHouse account or data loading is needed for its GitHub, property-sales, and Amazon examples. The defaults are Claude Sonnet 5, GPT-5.6 Luna, and Gemini 3.6 Flash; choose a model available to your account.

### Local ClickHouse

Install [clickhousectl](https://github.com/ClickHouse/clickhousectl), then run these commands **from this directory**. Named local servers belong to their project directory.

```sh
clickhousectl local use 26.8.2.7
clickhousectl local server start --name mcp-examples
clickhousectl local client --name mcp-examples --multiquery --queries-file fixture.sql
```

Use the HTTP port reported by the server command. For the default ports:

```sh
export CLICKHOUSE_HOST=localhost
export CLICKHOUSE_PORT=8123
export CLICKHOUSE_USER=default
export CLICKHOUSE_PASSWORD=
export CLICKHOUSE_SECURE=false
export MCP_PROMPT="Use mcp_demo.sales to calculate revenue by region."
```

This fixture returns North = 250 and South = 500. It is synthetic data. The notebooks' default playground questions need playground tables; use this prompt for the local fixture.

For a containerized MCP server, `localhost` means the container. Set `CLICKHOUSE_HOST=host.docker.internal` and make your dedicated local ClickHouse server reachable from Docker, or use a ClickHouse container on the same network. The Compose examples default to the public playground.

### ClickHouse Cloud

Create a [Cloud service](https://clickhouse.com/cloud). Apply the same [fixture.sql](fixture.sql) in its SQL console, and obtain connection details from **Connect**. Set:

```sh
export CLICKHOUSE_HOST=YOUR_SERVICE.clickhouse.cloud
export CLICKHOUSE_PORT=8443
export CLICKHOUSE_USER=YOUR_READER_USER
export CLICKHOUSE_PASSWORD=YOUR_READER_PASSWORD
export CLICKHOUSE_SECURE=true
export MCP_PROMPT="Use mcp_demo.sales to calculate revenue by region."
```

Use credentials with access to the tables you want the agent to read. Keep setup credentials separate from the agent's reader credentials. These examples launch the open-source MCP server against your service. Cloud's hosted remote MCP is a separate option; consult [ClickHouse MCP documentation](https://clickhouse.com/docs/use-cases/AI_ML/MCP).

## Notebooks and scripts

Launch one framework at a time, for example:

```sh
uv run --python 3.13 --with jupyterlab --with-requirements agno/requirements.txt jupyter lab --notebook-dir agno
```

Open the notebook at the URL printed by Jupyter. Its `%pip` cell installs into that notebook's kernel. Notebook outputs have been cleared, so old results do not appear to be current test evidence. An already exported API key is used without prompting again.

For script examples, change into the example directory and run `uv run --python 3.13 agent.py`. See its README for the entry point.

## Verify MCP without a model key

Against a running local ClickHouse server:

```sh
uv run smoke_test.py
```

The smoke test checks tool discovery, `list_databases`, paginated `list_tables`, `run_query`, and error reporting. It defaults to localhost unless you exported another connection.

For HTTP, generate a random token in `.env` and run:

```sh
docker compose up -d
uv run --env-file .env smoke_test.py --url http://127.0.0.1:8001/mcp
```

HTTP uses Streamable HTTP at `/mcp` and bearer authentication. The Compose server binds inside its container and explicitly allows the expected host headers. Stdio examples do not need HTTP authentication.

To check a framework's native adapter using the local server:

```sh
uv run --python 3.13 --with-requirements agno/requirements.txt tests/framework_smoke.py agno
```

These are protocol and adapter checks, not model-quality or live conversation tests.

## Optional live notebook check

This makes paid OpenAI calls with GPT-5.6 Luna. Load the shared fixture in local ClickHouse or Cloud, export its connection and `OPENAI_API_KEY`, then run one notebook:

```sh
uv run --python 3.13 --with-requirements agno/requirements.txt tests/live_notebook.py agno
```

The check executes the notebook's code cells in the selected environment and checks the fixture answer. It leaves saved notebook outputs unchanged.

## Cleanup

Stop local services from the same directory where you started them:

```sh
clickhousectl local server stop --name mcp-examples
docker compose down
```

Stop Jupyter and Python apps with Ctrl-C. App Compose volumes persist after `down`; `down -v` deletes their demo chats and settings. Remove `mcp_demo` from your local/Cloud database only when you no longer need the fixture. Stopping a Cloud service retains data and may retain charges; delete an unwanted service in the console.

[Companion documentation changes](CONTENT_UPDATES.md)
