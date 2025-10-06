from google.adk.agents import LlmAgent
from google.adk.tools.mcp_tool.mcp_toolset import MCPToolset
from google.adk.tools.mcp_tool.mcp_session_manager import StdioConnectionParams
from mcp import StdioServerParameters


root_agent = LlmAgent(
  model='gemini-2.0-flash',
  name='database_agent',
  instruction='Help the user query a ClickHouse database.',
  tools=[
    MCPToolset(
      connection_params=StdioConnectionParams(
        server_params = StdioServerParameters(
          command='uv',
          args=[
              "run",
              "--with",
              "mcp-clickhouse",
              "--python",
              "3.10",
              "mcp-clickhouse"
          ],
          env={
              "CLICKHOUSE_HOST": "sql-clickhouse.clickhouse.com",
              "CLICKHOUSE_PORT": "8443",
              "CLICKHOUSE_USER": "demo",
              "CLICKHOUSE_PASSWORD": "",
              "CLICKHOUSE_SECURE": "true",
              "CLICKHOUSE_VERIFY": "true",
              "CLICKHOUSE_CONNECT_TIMEOUT": "30",
              "CLICKHOUSE_SEND_RECEIVE_TIMEOUT": "30"
            }
        ),
        timeout=60,
      ),
    )
  ],
)