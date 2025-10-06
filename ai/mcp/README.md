# MCP Examples

## Cloning the repository

If you want to run these examples locally, you'll need to first clone the repository:

```
git clone https://github.com/ClickHouse/examples.git
cd examples/ai/mcp
```

## Jupyter notebooks

We have Jupyter Notebooks demonstrating how to build AI agents using various frameworks with the [ClickHouse MCP server](https://github.com/ClickHouse/mcp-clickhouse).

| Title | Stack | Notebook |
|-------|-------|----------|
| AI Agent with LlamaIndex and Claude Sonnet | LlamaIndex, Anthropic | [![View Notebook](https://img.shields.io/badge/view-notebook-orange?logo=jupyter)](https://github.com/clickhouse/examples/blob/main/ai/mcp/llamaindex/llamaindex.ipynb) |
| AI Agent with LangChain and Claude Sonnet | LangChain, Anthropic | [![View Notebook](https://img.shields.io/badge/view-notebook-orange?logo=jupyter)](https://github.com/clickhouse/examples/blob/main/ai/mcp/langchain/langchain.ipynb) |
| AI Agent with Agno and Claude Sonnet | Agno, Anthropic | [![View Notebook](https://img.shields.io/badge/view-notebook-orange?logo=jupyter)](https://github.com/clickhouse/examples/blob/main/ai/mcp/agno/agno.ipynb) |
| AI Agent with PydanticAI and Claude Sonnet | PydanticAI, Anthropic | [![View Notebook](https://img.shields.io/badge/view-notebook-orange?logo=jupyter)](https://github.com/clickhouse/examples/blob/main/ai/mcp/pydanticai/pydantic.ipynb) |
| AI Agent with DSPy and Claude Sonnet | DSPy, Anthropic | [![View Notebook](https://img.shields.io/badge/view-notebook-orange?logo=jupyter)](https://github.com/clickhouse/examples/blob/main/ai/mcp/dspy/dspy.ipynb) |
| AI Agent with OpenAI Agents | OpenAI | [![View Notebook](https://img.shields.io/badge/view-notebook-orange?logo=jupyter)](https://github.com/clickhouse/examples/blob/main/ai/mcp/openai-agents/openai-agents.ipynb) |

You can run the following command to launch the notebooks on your machine:

```
uv run --with jupyterlab jupyter lab --notebooks-dir mcp
```

You can then navigate to http://localhost:8888 to try out the notebooks.

## Streamlit app

We also have a Streamlit chat app that uses an Agno agent in the background.
You can find out more about this in the [Streamlit README](streamlit/README.md)


## Chainlit app

We have a Chainlit app too.
You can find out more about this in the [Chainlit README](chainlit/README.md)

## LibreChat app

We also have a LibreChat app.
This one requires a bit more setup, which you can find in the [LibreChat README](librechat/README.md)


## AnythingLLM app

We also have an AnythingLLM app.
This one also requires a bit more setup, which you can find in the [AnythingLLM README](anythingllm/README.md)

## Open WebUI app

We also have an Open WebUI app.
This one also requires a bit more setup, which you can find in the [Open WebUI README](open-webui/README.md)


## Google Agent Development Kit?

We also have a Google Agent Development Kit example.
You can find the example in the [Google ADK README](google-agent-development-kit/README.md).
