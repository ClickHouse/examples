import { spawn, type ChildProcess } from "node:child_process";
import { once } from "node:events";
import { createORPCClient } from "@orpc/client";
import { RPCLink } from "@orpc/client/fetch";
import type { ContractRouterClient } from "@orpc/contract";
import type { contract } from "../src/lib/contract";
import { createDb } from "../src/server/db";
export const origin = process.env.APP_ORIGIN ?? "http://127.0.0.1:4321";
export const client = createORPCClient<ContractRouterClient<typeof contract>>(
  new RPCLink({
    url: origin + "/rpc",
    headers: { Origin: origin, "X-Quote-Catalogue": "1" },
  }),
);
export const owner = () =>
  createDb({
    user: "quote_catalogue_owner",
    password: process.env.TEST_OWNER_PASSWORD,
  });
export async function start(): Promise<ChildProcess> {
  const child = spawn(process.execPath, ["scripts/start.mjs"], {
    env: process.env,
    stdio: ["ignore", "pipe", "pipe"],
  });
  let errors = "";
  child.stderr?.on("data", (d) => {
    errors += d.toString();
  });
  for (let i = 0; i < 100; i++) {
    if (child.exitCode !== null) throw new Error("Server exited: " + errors);
    try {
      if ((await fetch(origin + "/hire-guide")).ok) return child;
    } catch {}
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  child.kill("SIGTERM");
  throw new Error("Server readiness timed out: " + errors);
}
export async function stop(child?: ChildProcess) {
  if (child && child.exitCode === null) {
    child.kill("SIGTERM");
    await once(child, "exit");
  }
}
