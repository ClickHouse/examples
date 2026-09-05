# Companion corrections for the MCP refresh

These are concrete editorial changes to accompany the example update. **They have not been published.** The audit identified the backlinks below; owner assignment and remaining CMS/video coverage are still open. Public example paths have been retained.

## Shared replacement instructions

Replace unpinned MCP commands with:

```sh
uv tool run --python 3.13 --from mcp-clickhouse==0.6.0 mcp-clickhouse
```

Use the matching framework's requirements file and Python 3.13 in a separate environment. Link to the [shared setup](README.md) for playground/local/Cloud variables and the common fixture. Replace retired Claude model IDs with configurable `ANTHROPIC_MODEL` (default `claude-sonnet-5`). Describe `run_query` as the SQL tool, including in Claude's executable allowlist.

For HTTP examples, replace old `/sse` setup with Streamable HTTP `/mcp`, a generated bearer token, explicit bind address, and permitted Host headers. Use the checked-in Compose/configuration instead of a floating source clone. Do not publish a secret in a copied configuration.

Suggested dated note:

> The repository examples were refreshed on 5 September 2026. Dependency installation and MCP checks have passed. Eighteen integrations also passed live GPT-5.6 Luna checks at the scopes recorded in VALIDATION.md; browser walkthroughs and Claude Agent SDK conversations remain unverified. Use the repository README for current setup commands.

## Affected content and exact changes

| Content | Affected section and correction | Routing / status |
| --- | --- | --- |
| [How to build AI agents with MCP: 12 frameworks](https://clickhouse.com/blog/how-to-build-ai-agents-mcp-12-frameworks) | Replace install/model/MCP setup snippets for the linked notebooks. PydanticAI uses `MCPToolset`/`toolsets`; LlamaIndex uses `FunctionAgent`; Microsoft uses `Agent`/`OpenAIChatClient`; LangChain uses `create_agent` with its current MCP adapter; Upsonic uses `OpenAIResponsesModel` and an explicit async MCP context. CrewAI notebooks must await `kickoff_async`. Generic examples offer `LLM_PROVIDER=openai` with `OPENAI_MODEL=gpt-5.6-luna`; ADK uses LiteLLM for that path. State each framework's compatible MCP SDK major. Preserve historical outputs as dated examples or remove them; do not label them new results. | Original author/editor; owner not assigned. Corrections drafted here, publication pending. |
| [15 framework/app documentation pages](https://github.com/ClickHouse/clickhouse-docs/tree/89036285e33b88b424ebc397cce3cb70e9c2b5a9/docs/use-cases/AI_ML/MCP/ai_agent_libraries) | Agno, Chainlit, Claude Agent SDK, CopilotKit, CrewAI, DSPy, LangChain, LlamaIndex, MCP-Agent, Microsoft Agent Framework, OpenAI Agents, PydanticAI, Slackbot, Streamlit, Upsonic: copy current setup/API snippets from the corresponding example and link its validation limits. Chainlit requires `[[features.mcp.servers]]` configured on the server; remove the old browser-supplied command instructions. Streamlit uses Agno `RunContentEvent`. Chainlit's OpenAI entry point is `chat_openai.py`; its streaming tool loop handles multiple argument fragments and tool errors. | Docs maintainers; individual owner not assigned. Source paths verified by the audit; companion PR pending. |
| [Building an agentic application with ClickHouse MCP and CopilotKit](https://clickhouse.com/blog/building-an-agentic-application-with-clickhouse-mcp-server-and-copilotkit) | Replace installation/configuration/runtime/frontend snippets: Node 24, aligned CopilotKit 1.70.1, Next.js 16, `.env.local`, server-side MCP bearer configuration, v2 `BuiltInAgent`, `useFrontendTool`, and `useAgentContext`. Remove the source clone/`uv add fastmcp` steps and custom SSE bridge. Replace the future-tense Cloud remote-MCP claim with a link to the current [MCP docs](https://clickhouse.com/docs/use-cases/AI_ML/MCP). Retake chart screenshots after live UI validation. | Original author/editor; owner not assigned. Publication and screenshots pending. |
| [Tracing OpenAI agents with ClickStack](https://clickhouse.com/blog/tracing-openai-agents-clickstack) | Replace the exporter and table/view SQL with [clickhouse_processor.py](openai-agents/clickhouse_processor.py) and [schema.sql](openai-agents/schema.sql). Current span ID is `id`; export `parent_id`, timestamps, model and error. Use acknowledged inserts, flush/raise failures, nanosecond duration and derived error status. Replace the missing `ClickHouseSpanProcessor` import. Add explicit trace-destination variables and trace-source column mapping. Verify a successful and a failed live trace before updating screenshots. | Original author/editor and ClickStack docs maintainer; owners not assigned. Synthetic success/error export and a live Luna trace passed; live failure trace and ClickStack UI pending. |
| Open WebUI / AnythingLLM / LibreChat integration coverage | Update any copied snippets to the pinned native HTTP setups in this folder. Open WebUI supports native Streamable HTTP; AnythingLLM uses `type: "streamable"`; LibreChat needs `mcpSettings.allowedDomains` and the token header. | CMS/backlink coverage incomplete; no specific additional article asserted. |

The separate `ai/clickstack` observability examples and their [LLM observability article](https://clickhouse.com/blog/llm-observability-clickstack-mcp) are outside this refresh. Their tracing/container instructions must not be described as validated by the MCP app startup checks.

## Publication gate

Complete the remaining provider/UI checks in [VALIDATION.md](VALIDATION.md), assign the content owners, and prepare the corresponding docs/CMS revisions using these replacements. The README Cloud CTAs use the checked offer: [sign up](https://console.clickhouse.cloud/signUp), $300 credits for a 30-day trial. Recheck the offer at publication time.
