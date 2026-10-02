import { createApp } from "./app.ts";
import { database } from "./database.ts";
if (Deno.env.get("PGUSER") !== "places_reader") throw new Error("Server requires places_reader");
const port = Number(Deno.env.get("PORT") ?? "4000");
if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error("Invalid PORT");
const sql = database();
// Explicit files only: request paths are never translated to filesystem paths.
const assets = {
  "/": { body: await Deno.readTextFile("public/index.html"), type: "text/html" },
  "/app.js": { body: await Deno.readTextFile("public/app.js"), type: "application/javascript" },
  "/style.css": { body: await Deno.readTextFile("public/style.css"), type: "text/css" },
};
await sql`SELECT 1`;
const controller = new AbortController();
const stop = () => controller.abort();
const signals = ["SIGINT", "SIGTERM"] as const;
for (const signal of signals) Deno.addSignalListener(signal, stop);
const app = createApp(sql, assets);
// Oak's standard handle() API keeps middleware native while Deno owns HTTP shutdown.
const server = Deno.serve(
  {
    hostname: "127.0.0.1",
    port,
    signal: controller.signal,
    onListen: () => console.log("Nearby Places listening on loopback"),
  },
  async (request, info) =>
    await app.handle(request, info.remoteAddr) ?? new Response(null, { status: 404 }),
);
try {
  await server.finished;
} finally {
  for (const signal of signals) Deno.removeSignalListener(signal, stop);
  await sql.end({ timeout: 5 });
}
