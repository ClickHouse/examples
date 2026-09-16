import { AsyncLocalStorage } from "node:async_hooks";
import type { Pool } from "pg";
import type { createClient } from "@clickhouse/client-web";

type WorkersRuntime = {
  env: Env;
  postgres?: Pool;
  clickhouse?: ReturnType<typeof createClient>;
};

// Only the context carrier is global. Database sockets and credentials belong
// to one fetch/scheduled invocation and are never reused by another request.
const workersRuntime = new AsyncLocalStorage<WorkersRuntime>();

export function createWorkersRuntime(env: Env): WorkersRuntime {
  return { env };
}

export function runWorkersRuntime<T>(runtime: WorkersRuntime, work: () => T): T {
  return workersRuntime.run(runtime, work);
}

export function getWorkersRuntime() {
  return workersRuntime.getStore();
}

export function isWorkersRuntime(): boolean {
  return getWorkersRuntime() !== undefined;
}

export function runtimeEnvironment(key: string): string | undefined {
  const runtime = getWorkersRuntime();
  if (!runtime) return process.env[key];
  const value: unknown = Reflect.get(runtime.env, key);
  return typeof value === "string" ? value : undefined;
}

export async function closeWorkersRuntime(runtime: WorkersRuntime) {
  await Promise.all([runtime.postgres?.end(), runtime.clickhouse?.close()]);
}
