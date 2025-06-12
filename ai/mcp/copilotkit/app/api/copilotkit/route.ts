import {
  CopilotRuntime,
  AnthropicAdapter,
  copilotRuntimeNextJSAppRouterEndpoint,
} from "@copilotkit/runtime";
import { NextRequest } from "next/server";
import { MCPClient } from "@/app/utils/mcp-client";

const serviceAdapter = new AnthropicAdapter({model: "claude-3-7-sonnet-latest"});

const runtime = new CopilotRuntime({
  createMCPClient: async (config) => {
    const mcpClient = new MCPClient({
      serverUrl: config.endpoint,
    });
    await mcpClient.connect();
    return mcpClient;
  },
});

export const POST = async (req: NextRequest) => {
  const { handleRequest } = copilotRuntimeNextJSAppRouterEndpoint({
    runtime,
    serviceAdapter,
    endpoint: "/api/copilotkit",
  });

  return handleRequest(req);
};
