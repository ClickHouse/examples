import { createYoga } from "graphql-yoga";
import { schema } from "./graphql";
import { context } from "./context";
import { connectDatabase } from "./database";
const pool = await connectDatabase();
const origin = process.env.APP_ORIGIN || "http://127.0.0.1:3001";
const yoga = createYoga({
  schema,
  graphqlEndpoint: "/graphql",
  graphiql: false,
  logging: false,
  cors: false,
  context: () => context(pool),
});
const server = Bun.serve({
  hostname: "127.0.0.1",
  port: Number(process.env.PORT || 3001),
  async fetch(request) {
    const url = new URL(request.url);
    if (
      url.host !== new URL(origin).host ||
      (request.method !== "GET" && request.headers.get("origin") !== origin)
    )
      return new Response("Forbidden", { status: 403 });
    if (url.pathname === "/graphql") return yoga.fetch(request);
    if (url.pathname === "/") return new Response(Bun.file("dist/index.html"));
    if (/^\/assets\/[a-zA-Z0-9_.-]+$/.test(url.pathname))
      return new Response(Bun.file("dist" + url.pathname));
    return new Response("Not found", { status: 404 });
  },
});
console.log("Collection studio listening on " + origin);
for (const signal of ["SIGTERM", "SIGINT"] as const)
  process.on(signal, async () => {
    server.stop();
    await pool.end();
    process.exit(0);
  });
