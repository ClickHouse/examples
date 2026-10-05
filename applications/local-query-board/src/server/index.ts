import { connectDatabase, database } from "./database";
import { createApp } from "./app";
const origin = process.env.APP_ORIGIN ?? "http://127.0.0.1:3000";
const parsed = new URL(origin);
if (
  parsed.protocol !== "http:" ||
  parsed.hostname !== "127.0.0.1" ||
  parsed.pathname !== "/"
)
  throw new Error("APP_ORIGIN must be an HTTP loopback origin");
const engine = process.env.ELECTRIC_URL ?? "http://127.0.0.1:3005";
if (new URL(engine).hostname !== "127.0.0.1")
  throw new Error("Electric must be local to this workbench");
if (!process.env.ELECTRIC_SECRET)
  throw new Error("ELECTRIC_SECRET is required");
const pool = await connectDatabase();
const app = createApp(
  database(pool),
  origin,
  engine,
  process.env.ELECTRIC_SECRET,
);
app.get("*", async (c) => {
  const path = c.req.path === "/" ? "/index.html" : c.req.path;
  if (path.includes("..")) return c.notFound();
  const file = Bun.file(`dist${path}`);
  if (await file.exists()) return new Response(file);
  return c.notFound();
});
const server = Bun.serve({
  hostname: "127.0.0.1",
  port: Number(parsed.port || 80),
  fetch: app.fetch,
  idleTimeout: 60,
});
console.log(`Fieldwork on ${origin}`);
for (const signal of ["SIGINT", "SIGTERM"] as const)
  process.on(signal, async () => {
    await server.stop(true);
    await pool.end();
    process.exit(0);
  });
