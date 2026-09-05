# MCP refresh validation — 5 September 2026

All 19 integrations were refreshed. **18 passed live GPT-5.6 Luna/MCP checks** at the scopes below. Claude Agent SDK received configuration/protocol checks only. Browser walkthroughs, actual Slack delivery, a real ClickHouse Cloud service, and ClickStack visualization remain unverified.

## Environment and dependency selection

All source edits, installs, builds, and example execution ran in the OrbStack VM `examples-sandbox`, checkout `/home/al/work/examples`, branch `update/ai-mcp-2026-09`. Baseline: `3d07542768956664808b0371af3329732dd200af`.

- Ubuntu 26.04.1 arm64; CPython 3.13.15; uv 0.12.10.
- Node.js 24.20.0 LTS; npm 11.19.0.
- clickhousectl 0.4.2; **local ClickHouse 26.8.2.7**.
- Docker 29.1.3 with Compose.
- **MCP server 0.6.0** in an isolated uv tool environment or its versioned container.
- Package versions checked against primary PyPI/npm metadata and upstream release/image tags on this date. Exact direct framework pins are in each requirements file; Slack and CopilotKit also have resolved lockfiles. Python requirements outside Slack do not freeze every transitive dependency.

The [example index](README.md#choose-an-example) lists the selected framework/app releases. Compatibility exceptions found by installing and exercising the packages:

| Package | Selected version / reason |
| --- | --- |
| MCP SDK in Chainlit, mcp-agent, Upsonic | 1.28.1. The current integrations still depend on 1.x APIs; SDK 2.x caused import or request API failures. |
| FastMCP in Upsonic | 3.4.7. Its current integration is incompatible with FastMCP 4 / MCP 2. |
| Google ADK | 2.8.0 with the `mcp` extra. MCP is now optional. |
| PydanticAI | 2.40.0 with `MCPToolset`; httpx 0.28.1 remains required alongside the newer transport's HTTPX2. |
| TypeScript | 6.0.3. TypeScript 7.0.2 broke the installed ESLint parser. |
| ESLint | 9.39.5. ESLint 10.10.0 broke the installed React lint plugin's `getFilename` call. |
| LibreChat | 0.8.7 stable. The newer 0.8.8 release candidate was excluded. |

OpenAI examples default to configurable `OPENAI_MODEL=gpt-5.6-luna`. Generic examples also support `LLM_PROVIDER=openai`; ADK uses LiteLLM for this path. Alternative defaults are Claude Sonnet 5 and Gemini 3.6 Flash, checked against the [Anthropic model overview](https://platform.claude.com/docs/en/models/overview) and [Google model reference](https://ai.google.dev/gemini-api/docs/models/gemini-3.6-flash), but not called during this validation.

The user's OpenAI credential stayed in their laptop's local `.env`. A temporary relay forwarded only Luna requests to OpenAI with response storage disabled and output/request/cost limits. The VM used a dummy relay token. The relay has been stopped. The ledger records 80 requests, 78 successful responses, 62,180 input tokens and 2,798 output tokens: a conservative estimate of **$0.019 (about $0.02)** using the [Luna pricing reference](https://developers.openai.com/api/docs/models/gpt-5.6-luna), not a billing receipt. Two rejected requests exposed server-side response-ID reuse with storage disabled; the final clients passed using local conversation state.

## Passed checks

| Scope | Evidence |
| --- | --- |
| Installation | All 14 Python requirements environments installed; `uv pip check` passed for every environment and the Slack lockfile environment. CopilotKit installed and built in Node 24. |
| Shared MCP contract | Stdio and authenticated Streamable HTTP: list tools, databases, paginated tables, SELECT 1/version, malformed query reported as an error. HTTP rejected missing bearer credentials (401) and an unapproved Host header (421). |
| Shared local fixture | Four rows; North revenue 250, South 500. Reapplying the SQL did not duplicate rows. |
| 12 framework integrations | Agno, Claude Agent SDK configuration, CrewAI, DSPy, Google ADK, LangChain, LlamaIndex, mcp-agent, Microsoft Agent Framework, OpenAI Agents, PydanticAI, and Upsonic constructed their current integrations and ran SELECT 1 through MCP against local 26.8.2.7. |
| Chainlit | Started from its own directory with the committed 2.12 configuration. The configured MCP subprocess queried ClickHouse. Offline tests exercised multiple tool results, signed thinking preservation, failed calls, and disconnect cleanup. HTTP startup returned 200. |
| Streamlit | AppTest and HTTP health passed. A partial stream followed by an exception reached the caller instead of blocking the queue. Agno's native MCP query was separately checked. |
| Slack | Locked install/imports; real Vega-Lite PNG rendering; mocked `files_upload_v2`; temporary files removed after success/failure; visible query failure response. No Slack API traffic was sent. |
| CopilotKit | ESLint and production build passed after the final dependency changes. Runtime startup and agent-info endpoint passed. Native JavaScript MCP client discovered tools, queried SELECT 1, and received a failed-query result. |
| Open WebUI | Versioned container healthy; its own Python MCP client discovered tools, queried SELECT 1, and raised on invalid SQL. |
| AnythingLLM | Versioned container started; its own MCP compatibility layer loaded the configured server and queried SELECT 1. |
| LibreChat | Final standalone Compose stack started after adding `mcpSettings.allowedDomains`; its native `MCPConnection` discovered tools, queried SELECT 1, and returned an invalid-SQL error. |
| OpenAI tracing | Actual SDK success/error spans exported to the included schema; exact nanosecond duration, correct status/message, and visible rejected-insert failure checked. Temporary database removed by the test. |
| Source | Python and notebook code parsed/compiled; old notebook outputs cleared. |

The packaged app MCP containers used the public SQL playground, which reported **26.9.1.36875**. This is separate from the local 26.8.2.7 run and **is not a ClickHouse Cloud service validation**.

The adapter checks above are independent of the live checks below. The Claude check validates its configured allowlist and exercises its stdio configuration; it does not establish Claude's model behavior or permission enforcement.

## Passed live Luna checks

| Integration / entry point | Evidence and boundary |
| --- | --- |
| Agno, CrewAI, DSPy, LangChain, LlamaIndex, mcp-agent, Microsoft Agent Framework, OpenAI Agents, PydanticAI, Upsonic | Executed the actual code cells of all 10 OpenAI-capable notebooks, including top-level awaits. Each queried the local fixture and answered North 250 / South 500. Saved notebook outputs remain cleared. |
| Script entry points | OpenAI Agents without tracing, CrewAI, mcp-agent, and Upsonic scripts completed live fixture queries. CrewAI's notebook now awaits `kickoff_async`; Upsonic's explicit MCP context closes cleanly. |
| Google ADK | Its actual `root_agent` ran via the ADK Runner and LiteLLM, queried the local fixture, and answered correctly. |
| Chainlit | The OpenAI streaming loop queried the fixture, answered a history follow-up (South exceeds North by 250), and reported invalid SQL. Chainlit UI/session objects were supplied by a test harness; the model and MCP connection were real. |
| Streamlit | Actual AppTest chat input exercised the app, Agno, Luna and MCP. The stored answer contained both fixture totals; no app errors. |
| Slackbot | Actual handler/model/MCP query returned the fixture answer with Slack transport mocked. No Slack messages were sent. |
| CopilotKit | HTTP request to the v2 runtime queried the fixture and emitted `generateChart` arguments with bar data North 250 / South 500 and a short title. Browser chart rendering was not tested. |
| Open WebUI | Its native chat pipeline completed a saved conversation containing `run_query`, its result, and the final answer to `SELECT version()`. A local test session supplied the UI context. |
| LibreChat | Installed native `Run`/`StandardGraph` and `MCPConnection` components completed a Luna tool query and answer to `SELECT version()`. This did not exercise browser login or the full conversation HTTP route. |
| AnythingLLM | Native AIbitat and MCP compatibility plugins completed a Luna query and answer to `SELECT version()`. The UI introspection callback was stubbed; workspace onboarding and browser interaction were not tested. |
| OpenAI tracing | An actual Luna agent run exported nine spans to local ClickHouse, including the model and `run_query` spans, with no recorded errors. The temporary trace database was removed. This supplements the synthetic success/error/rejected-insert regressions. |

The first 15 integrations used the local ClickHouse **26.8.2.7** fixture. The three packaged apps used the public playground, **26.9.1.36875**. No other model was used for paid tests.

## Reproduce the checks

Start local ClickHouse using the [shared setup](README.md#local-clickhouse), then from `ai/mcp`:

```sh
export CLICKHOUSE_HOST=localhost CLICKHOUSE_PORT=8123
export CLICKHOUSE_USER=default CLICKHOUSE_PASSWORD= CLICKHOUSE_SECURE=false
uv run smoke_test.py
uv run --python 3.13 --with-requirements agno/requirements.txt tests/framework_smoke.py agno
uv run --python 3.13 --with-requirements chainlit/requirements.txt tests/app_smoke.py chainlit
uv run --python 3.13 --with-requirements streamlit/requirements.txt tests/app_smoke.py streamlit
uv run --python 3.13 --with-requirements openai-agents/requirements.txt tests/tracing_smoke.py
```

For an optional paid notebook run after exporting `OPENAI_API_KEY` and loading the fixture:

```sh
uv run --python 3.13 --with-requirements agno/requirements.txt tests/live_notebook.py agno
```

This helper is restricted to Luna, executes notebook code cells, and checks the fixture answer without saving outputs. The live app checks used the app-specific APIs/components described above; the offline smoke suite does not reproduce those paid checks.

Replace `agno` in both places to test another framework. Slack uses `uv run --project slackbot --locked tests/app_smoke.py slackbot`. CopilotKit has `npm run lint`, `npm run build`, and `npm run test:mcp`; HTTP checks require its MCP server to be running.

## Remaining checks and limitations

- Validate Anthropic/Gemini paths separately if they are to be claimed working. Only Luna was authorized for paid tests; Claude Agent SDK cannot be validated with it. Follow-up and failed-SQL model behavior were checked in Chainlit, not exhaustively across every integration.
- Check streamed rendering, MCP selection, and charts in a browser. No in-app browser was connected; downloading a VM Playwright browser repeatedly timed out. HTTP startup and native adapter checks do not establish that these UI journeys work.
- Test Claude's actual tool permission flow, Slack delivery in an authorized test workspace, and AnythingLLM Desktop separately.
- Apply the fixture and trace schema to a real Cloud service and record its server version. Check the trace view in ClickStack.
- Complete the [companion content corrections](CONTENT_UPDATES.md) before presenting the published tutorials as refreshed.

The final CopilotKit `npm audit` reports **6 affected packages: 1 high, 1 moderate, 4 low**. These remain under legacy AI SDK provider dependencies: `@ai-sdk/provider-utils@3.0.36`, `undici@5.29.0`, and dependent Google/Anthropic compatibility packages. Their latest compatible major releases remain affected. Same-major overrides update `body-parser` to 1.20.6 and `qs` to 6.16.0. Forcing a provider-utils/Undici major upgrade has not been validated and was not applied. This is not a claim that repository security alerts are all resolved.

Existing PRs [#386](https://github.com/ClickHouse/examples/pull/386) and [#391](https://github.com/ClickHouse/examples/pull/391) were inspected. Their narrow MCP/Next.js updates are superseded by this tested dependency selection; avoid merging overlapping lockfile changes blindly.

## Primary migration references

- [ClickHouse MCP releases and transport contract](https://github.com/ClickHouse/mcp-clickhouse)
- [Agno MCP](https://docs.agno.com/tools/mcp/overview)
- [PydanticAI MCP client](https://pydantic.dev/docs/ai/mcp/client/)
- [LangChain MCP](https://docs.langchain.com/oss/python/langchain/mcp) — the selected built-in adapter is in its beta namespace.
- [LlamaIndex agents](https://developers.llamaindex.ai/python/framework/understanding/agent/)
- [Microsoft Agent Framework MCP](https://learn.microsoft.com/en-us/agent-framework/user-guide/model-context-protocol/using-mcp-tools)
- [CopilotKit MCP](https://docs.copilotkit.ai/mcp-servers)
- [Chainlit MCP migration](https://github.com/Chainlit/chainlit/blob/main/docs/security-advisory-2026-mcp.md)
- [Open WebUI native MCP](https://docs.openwebui.com/features/extensibility/mcp/)
- [LibreChat MCP](https://www.librechat.ai/docs/configuration/librechat_yaml/object_structure/mcp_servers)
- [AnythingLLM MCP](https://docs.anythingllm.com/mcp-compatibility/overview)

The [Cloud offer](https://clickhouse.com/cloud) advertised $300 credits for a 30-day trial when checked; recheck before publishing.
