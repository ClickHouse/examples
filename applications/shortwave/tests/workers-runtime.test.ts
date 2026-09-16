import assert from "node:assert/strict";
import { test } from "node:test";
import {
  createWorkersRuntime,
  getWorkersRuntime,
  isWorkersRuntime,
  runWorkersRuntime,
  runtimeEnvironment,
} from "../src/server/runtime";

test("Workers invocations keep environment and resources isolated across awaits", async () => {
  // Binding methods are intentionally absent: this checks context propagation
  // without opening network connections or requiring deployment credentials.
  const first = createWorkersRuntime({ APP_URL: "https://first.example" } as Env);
  const second = createWorkersRuntime({ APP_URL: "https://second.example" } as Env);
  let releaseFirst!: () => void;
  const firstCanFinish = new Promise<void>((resolve) => { releaseFirst = resolve; });

  assert.equal(isWorkersRuntime(), false);
  await Promise.all([
    runWorkersRuntime(first, async () => {
      assert.equal(runtimeEnvironment("APP_URL"), "https://first.example");
      await firstCanFinish;
      assert.equal(getWorkersRuntime(), first);
      assert.equal(runtimeEnvironment("APP_URL"), "https://first.example");
    }),
    runWorkersRuntime(second, async () => {
      await Promise.resolve();
      assert.equal(getWorkersRuntime(), second);
      assert.equal(runtimeEnvironment("APP_URL"), "https://second.example");
      releaseFirst();
    }),
  ]);
  assert.equal(isWorkersRuntime(), false);
  assert.equal(runtimeEnvironment("APP_URL"), process.env.APP_URL);
});

test("Workers missing bindings do not fall back to a Node process credential", () => {
  const key = "SHORTWAVE_RUNTIME_ISOLATION_TEST";
  process.env[key] = "node-only";
  try {
    assert.equal(runtimeEnvironment(key), "node-only");
    runWorkersRuntime(createWorkersRuntime({} as Env), () => {
      assert.equal(runtimeEnvironment(key), undefined);
    });
  } finally {
    delete process.env[key];
  }
});
