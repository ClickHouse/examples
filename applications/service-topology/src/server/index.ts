import { Elysia } from "elysia";
import { connectDatabase } from "./database";
import { createApi } from "./app";
import { allowedRequest } from "./origin";
const { db, client } = await connectDatabase();
const app = new Elysia()
  .onRequest(({ request, status }) => {
    if (!allowedRequest(request)) return status(403);
  })
  .use(createApi(db))
  .get("/", () => Bun.file("dist/index.html"))
  .get("/assets/:file", ({ params, status }) =>
    /^[a-zA-Z0-9_.-]+$/.test(params.file)
      ? Bun.file("dist/assets/" + params.file)
      : status(404),
  )
  .listen({ port: Number(process.env.PORT || 3000), hostname: "127.0.0.1" });
console.log("Service atlas listening on http://127.0.0.1:" + app.server?.port);
for (const signal of ["SIGTERM", "SIGINT"] as const)
  process.on(signal, async () => {
    await app.stop();
    await client.close();
    process.exit(0);
  });
