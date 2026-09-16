import { loadEnvFile } from "node:process";
import { setTimeout } from "node:timers/promises";
import { flushOutbox } from "../src/server/service";
import { closeDatabases } from "../src/server/db";

try {
  loadEnvFile(".env");
} catch (error) {
  if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
}
const watch = process.argv.includes("--watch");
let stopped = false;
process.on("SIGTERM", () => {
  stopped = true;
});
process.on("SIGINT", () => {
  stopped = true;
});
try {
  do {
    try {
      const result = await flushOutbox();
      if (!watch || result.delivered || result.failed)
        console.log(JSON.stringify(result));
      if (!watch && result.failed) process.exitCode = 1;
    } catch {
      console.error(
        "Event delivery failed; durable events remain queued for retry.",
      );
      if (!watch) process.exitCode = 1;
    }
    if (watch && !stopped) await setTimeout(2_000);
  } while (watch && !stopped);
} finally {
  await closeDatabases();
}
