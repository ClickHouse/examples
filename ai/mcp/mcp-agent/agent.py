# /// script
# requires-python = ">=3.9"
# dependencies = [
#   "mcp-agent",
#   "openai"
# ]
# ///

import asyncio

from mcp_agent.app import MCPApp
from mcp_agent.agents.agent import Agent
from mcp_agent.workflows.llm.augmented_llm_openai import OpenAIAugmentedLLM
from mcp_agent.config import Settings, MCPSettings, MCPServerSettings, OpenAISettings

env = {
    "CLICKHOUSE_HOST": "sql-clickhouse.clickhouse.com",
    "CLICKHOUSE_PORT": "8443",
    "CLICKHOUSE_USER": "demo",
    "CLICKHOUSE_PASSWORD": "",
    "CLICKHOUSE_SECURE": "true",
    "CLICKHOUSE_VERIFY": "true",
    "CLICKHOUSE_CONNECT_TIMEOUT": "30",
    "CLICKHOUSE_SEND_RECEIVE_TIMEOUT": "30"
}


settings = Settings(
    execution_engine="asyncio",
    openai=OpenAISettings(
        default_model="gpt-5-mini-2025-08-07",
    ),
    mcp=MCPSettings(
        servers={
            "clickhouse": MCPServerSettings(
                command='uv',
                args=[
                    "run",
                    "--with", "mcp-clickhouse",
                    "--python", "3.10",
                    "mcp-clickhouse"
                ],
                env=env
            ),
        }
    ),
)

app = MCPApp(name="mcp_basic_agent", settings=settings)

async def example_usage():
    async with app.run() as mcp_agent_app:
        logger = mcp_agent_app.logger
        data_agent = Agent(
            name="database-anayst",
            instruction="""You can answer questions with help from a ClickHouse database.""",
            server_names=["clickhouse"],
        )

        async with data_agent:
            llm = await data_agent.attach_llm(OpenAIAugmentedLLM)
            result = await llm.generate_str(
                message="Tell me about UK property prices in 2025. Use ClickHouse to work it out."
            )
            
            logger.info(result)

if __name__ == "__main__":
    asyncio.run(example_usage())