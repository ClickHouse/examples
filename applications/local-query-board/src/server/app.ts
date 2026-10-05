import { z } from "zod";
import { Hono } from "hono";
import type { Database } from "./database";
import { shapeUrl } from "./proxy";
import { createTask, updateTask, WriteError } from "./writes";
export function createApp(
  db: Database,
  origin: string,
  engine: string,
  secret: string,
) {
  const app = new Hono();
  app.use("*", async (c, next) => {
    if (c.req.header("host") !== new URL(origin).host)
      return c.json({ error: "Unexpected host" }, 403);
    if (
      (c.req.method !== "GET" || c.req.header("origin")) &&
      c.req.header("origin") !== origin
    )
      return c.json({ error: "Unexpected origin" }, 403);
    await next();
  });
  app.get("/api/shapes/:kind", async (c) => {
    let url: URL;
    try {
      url = shapeUrl(c.req.url, c.req.param("kind"), engine, secret);
    } catch {
      return c.json({ error: "Unsupported shape or parameter" }, 400);
    }
    const response = await fetch(url, { signal: c.req.raw.signal });
    const headers = new Headers(response.headers);
    headers.delete("content-encoding");
    headers.delete("content-length");
    // Same-origin proxy: upstream CORS policy is not this local app's policy.
    for (const key of [...headers.keys()])
      if (key.startsWith("access-control-")) headers.delete(key);
    headers.set("cache-control", "no-store");
    return new Response(response.body, { status: response.status, headers });
  });
  app.post("/api/tasks", async (c) =>
    c.json(await createTask(db, await c.req.json()), 201),
  );
  app.patch("/api/tasks/:id", async (c) => {
    if (!z.string().uuid().safeParse(c.req.param("id")).success)
      return c.json({ error: "Invalid task ID" }, 400);
    return c.json(await updateTask(db, c.req.param("id"), await c.req.json()));
  });
  app.get("/api/health", (c) => c.json({ ok: true }));
  app.onError((error, c) => {
    if (error instanceof WriteError)
      return c.json({ error: error.message }, error.status);
    if (error instanceof SyntaxError)
      return c.json({ error: "Invalid JSON" }, 400);
    console.error("Request failed", error.name);
    return c.json({ error: "The request could not be completed" }, 500);
  });
  return app;
}
