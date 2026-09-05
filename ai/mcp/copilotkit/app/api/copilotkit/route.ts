import { BuiltInAgent, CopilotRuntime, createCopilotRuntimeHandler } from "@copilotkit/runtime/v2";
import { clickhouseMcpConfig } from "@/app/utils/mcp-client";

export const runtime = "nodejs";
let handler: ReturnType<typeof createCopilotRuntimeHandler> | undefined;

function getHandler() {
  if (!handler) {
    const copilotRuntime = new CopilotRuntime({
      agents: {
        default: new BuiltInAgent({
          model: process.env.LLM_PROVIDER === "openai"
            ? `openai:${process.env.OPENAI_MODEL || "gpt-5.6-luna"}`
            : `anthropic:${process.env.ANTHROPIC_MODEL || "claude-sonnet-5"}`,
          maxSteps: 12,
          prompt: "Help users analyze ClickHouse data. Discover tables before querying. Use generateChart to visualize query results; keep chart titles under 30 characters.",
          mcpServers: [clickhouseMcpConfig()],
        }),
      },
    });
    handler = createCopilotRuntimeHandler({ runtime: copilotRuntime, basePath: "/api/copilotkit" });
  }
  return handler;
}
export const GET = (request: Request) => getHandler()(request);
export const POST = (request: Request) => getHandler()(request);
