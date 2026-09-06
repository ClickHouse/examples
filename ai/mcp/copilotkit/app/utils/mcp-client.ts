import type { MCPClientConfigHTTP } from "@copilotkit/runtime/v2";

/** Server-owned endpoint and credentials, shared by the runtime and protocol check. */
export function clickhouseMcpConfig(): MCPClientConfigHTTP {
  const token = process.env.CLICKHOUSE_MCP_AUTH_TOKEN;
  if (!token) throw new Error("Set CLICKHOUSE_MCP_AUTH_TOKEN in .env.local");
  return {
    type: "http",
    url: process.env.MCP_ENDPOINT || "http://127.0.0.1:8000/mcp",
    options: { requestInit: { headers: { Authorization: `Bearer ${token}` } } },
  };
}
