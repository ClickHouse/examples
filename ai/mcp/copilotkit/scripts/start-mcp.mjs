import { spawn } from "node:child_process";
if (!process.env.CLICKHOUSE_MCP_AUTH_TOKEN) {
  throw new Error("Set CLICKHOUSE_MCP_AUTH_TOKEN in .env.local");
}
const child = spawn("uv", ["tool", "run", "--python", "3.13", "--from", "mcp-clickhouse==0.6.0", "mcp-clickhouse"], {
  stdio: "inherit",
  env: { ...process.env, CLICKHOUSE_MCP_SERVER_TRANSPORT: "http", CLICKHOUSE_MCP_BIND_HOST: "127.0.0.1" },
});
for (const signal of ["SIGINT", "SIGTERM"]) process.on(signal, () => child.kill(signal));
child.on("error", error => { console.error(error); process.exitCode = 1; });
child.on("exit", code => { process.exitCode = code ?? 1; });
