# GenAI Examples

Jupyter Notebooks demonstrating how to build AI agents using various frameworks with the [ClickHouse MCP server](https://github.com/ClickHouse/mcp-clickhouse).

| Title | Stack | Notebook |
|-------|-------|----------|
| AI Agent with LlamaIndex and Claude Sonnet | LlamaIndex, Anthropic | [![View Notebook](https://img.shields.io/badge/view-notebook-orange?logo=jupyter)](https://github.com/clickhouse/examples/blob/main/GenAI-Examples/mcp-clients/agents/llama_index.ipynb) |
| AI Agent with LangChain and Claude Sonnet | LangChain, Anthropic | [![View Notebook](https://img.shields.io/badge/view-notebook-orange?logo=jupyter)](https://github.com/clickhouse/examples/blob/main/GenAI-Examples/mcp-clients/agents/langchain.ipynb) |
| AI Agent with Agno and Claude Sonnet | Agno, Anthropic | [![View Notebook](https://img.shields.io/badge/view-notebook-orange?logo=jupyter)](https://github.com/clickhouse/examples/blob/main/GenAI-Examples/mcp-clients/agents/agno.ipynb) |
| AI Agent with PydanticAI and Claude Sonnet | PydanticAI, Anthropic | [![View Notebook](https://img.shields.io/badge/view-notebook-orange?logo=jupyter)](https://github.com/clickhouse/examples/blob/main/GenAI-Examples/mcp-clients/agents/pydantic.ipynb) |
| AI Agent with DSPy and Claude Sonnet | DSPy, Anthropic | [![View Notebook](https://img.shields.io/badge/view-notebook-orange?logo=jupyter)](https://github.com/clickhouse/examples/blob/main/GenAI-Examples/mcp-clients/agents/dspy.ipynb) |

## Running locally

If you want to run these notebooks locally, you'll need to first clone the repository:


```
git clone git@github.com:mneedham/clickhouse-examples.git
cd clickhouse-examples/genai-examples
```

And then run the following command to launch the notebooks:

```
uv run --with jupyterlab jupyter lab --notebooks-dir mcp-clients
```

You can then navigate to http://localhost:8888 to try out the notebooks.