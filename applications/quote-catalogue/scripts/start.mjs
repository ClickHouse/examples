const host = process.env.HOST ?? "127.0.0.1";
if (!["127.0.0.1", "::1"].includes(host))
  throw new Error("HOST must be loopback");
process.env.HOST = host;
process.env.PORT ??= "4321";
await import("../dist/server/entry.mjs");
