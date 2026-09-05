import os
from google.adk.agents import LlmAgent
from google.adk.models.lite_llm import LiteLlm
from google.adk.tools.mcp_tool.mcp_toolset import McpToolset
from google.adk.tools.mcp_tool.mcp_session_manager import StdioConnectionParams
from mcp import StdioServerParameters


root_agent = LlmAgent(
  model=(LiteLlm(model="openai/" + os.getenv("OPENAI_MODEL", "gpt-5.6-luna"),
                 api_base=os.getenv("OPENAI_BASE_URL", "https://api.openai.com/v1"))
         if os.getenv("LLM_PROVIDER", "google") == "openai"
         else os.getenv("GOOGLE_MODEL", "gemini-3.6-flash")),
  name='database_agent',
  instruction='Help the user query a ClickHouse database.',
  tools=[
    McpToolset(
      connection_params=StdioConnectionParams(
        server_params = StdioServerParameters(
          command='uv',
          args=["tool", "run", "--python", "3.13", "--from", "mcp-clickhouse==0.6.0", "mcp-clickhouse"],
          env={
              "CLICKHOUSE_HOST": os.getenv("CLICKHOUSE_HOST", 'sql-clickhouse.clickhouse.com'),
              "CLICKHOUSE_PORT": os.getenv("CLICKHOUSE_PORT", '8443'),
              "CLICKHOUSE_USER": os.getenv("CLICKHOUSE_USER", 'demo'),
              "CLICKHOUSE_PASSWORD": os.getenv("CLICKHOUSE_PASSWORD", ''),
              "CLICKHOUSE_SECURE": os.getenv("CLICKHOUSE_SECURE", 'true'),
              "CLICKHOUSE_VERIFY": os.getenv("CLICKHOUSE_VERIFY", 'true'),
              "CLICKHOUSE_CONNECT_TIMEOUT": os.getenv("CLICKHOUSE_CONNECT_TIMEOUT", '30'),
              "CLICKHOUSE_SEND_RECEIVE_TIMEOUT": os.getenv("CLICKHOUSE_SEND_RECEIVE_TIMEOUT", '30')
            }
        ),
        timeout=60,
      ),
    )
  ],
)