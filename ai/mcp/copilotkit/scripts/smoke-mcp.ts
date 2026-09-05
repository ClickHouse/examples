import assert from "node:assert/strict";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";
import { clickhouseMcpConfig } from "../app/utils/mcp-client";
async function main() {
  const config = clickhouseMcpConfig();
  const client = new Client({ name: "copilotkit-example-check", version: "1.0.0" });
  try {
    await client.connect(new StreamableHTTPClientTransport(new URL(config.url), config.options));
    const tools = await client.listTools();
    assert(tools.tools.some(tool => tool.name === "run_query"));
    const result = await client.callTool({ name: "run_query", arguments: { query: "SELECT 1 AS value" } });
    assert(!result.isError);
    const content = result.content as { type: string; text: string }[];
    assert.deepEqual(JSON.parse(content[0].text).rows, [[1]]);
    const invalid = await client.callTool({ name: "run_query", arguments: { query: "SELECT missing_column FROM system.one" } });
    assert.equal(invalid.isError, true);
    console.log("Passed: authenticated HTTP discovery, SELECT 1, and query errors");
  } finally {
    await client.close();
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
