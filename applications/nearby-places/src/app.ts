import { Application, Router } from "@oak/oak";
import { InputError, parseSearch } from "./input.ts";
import { nearbyQuery } from "./places.ts";
import type { Database } from "./database.ts";
export function createApp(sql: Database, assets: Record<string, { body: string; type: string }>) {
  const app = new Application();
  app.use(async (ctx, next) => {
    ctx.response.headers.set(
      "Content-Security-Policy",
      "default-src 'self'; connect-src 'self'; script-src 'self'; style-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'",
    );
    ctx.response.headers.set("X-Content-Type-Options", "nosniff");
    ctx.response.headers.set("Referrer-Policy", "no-referrer");
    try {
      if (ctx.request.url.href.length > 2048) {
        ctx.response.status = 414;
        ctx.response.body = { error: "url_too_long" };
        return;
      }
      await next();
    } catch (error) {
      if (error instanceof InputError) {
        ctx.response.status = 400;
        ctx.response.body = { error: error.message };
      } else {
        console.error("Nearby search failed");
        ctx.response.status = 503;
        ctx.response.body = { error: "search_unavailable" };
      }
    }
  });
  const router = new Router();
  router.get("/health", (ctx) => {
    ctx.response.body = { ok: true };
  });
  router.get("/api/nearby", async (ctx) => {
    const search = parseSearch(ctx.request.url.searchParams);
    ctx.response.body = { search, places: await nearbyQuery(sql, search), sampleData: true };
    ctx.response.headers.set("Cache-Control", "no-store");
  });
  for (const [path, asset] of Object.entries(assets)) {
    router.get(path, (ctx) => {
      ctx.response.type = asset.type;
      ctx.response.body = asset.body;
    });
  }
  app.use(router.routes());
  app.use(router.allowedMethods());
  app.use((ctx) => {
    ctx.response.status = 404;
    ctx.response.body = { error: "not_found" };
  });
  return app;
}
