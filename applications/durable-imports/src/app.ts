import express, { type ErrorRequestHandler } from "express";
import { authorize } from "./auth.js";
import { ApiError, MAX_BYTES, uuid } from "./input.js";
import type { Imports } from "./imports.js";
export function createApp(imports: Imports) {
  const app = express();
  app.disable("x-powered-by");
  app.get("/health", (_, res) => res.json({ ok: true }));
  app.use(
    "/imports",
    authorize(),
    express.json({ limit: MAX_BYTES, strict: true }),
  );
  app.post("/imports", async (req, res) => {
    const result = await imports.submit(res.locals.accountId, req.body);
    res
      .status(result.replay ? 200 : 202)
      .location(`/imports/${result.id}`)
      .json(result);
  });
  app.get("/imports/:id", async (req, res) => {
    if (!uuid(req.params.id)) throw new ApiError(400, "invalid_import_id");
    res.json(
      await imports.status(res.locals.accountId, req.params.id.toLowerCase()),
    );
  });
  app.get("/imports/:id/results", async (req, res) => {
    if (!uuid(req.params.id)) throw new ApiError(400, "invalid_import_id");
    res.json({
      rows: await imports.results(
        res.locals.accountId,
        req.params.id.toLowerCase(),
      ),
    });
  });
  app.use((_, res) => res.status(404).json({ error: "not_found" }));
  const errors: ErrorRequestHandler = (error, _req, res, _next) => {
    if (error instanceof ApiError) {
      if (error.status === 429) res.set("Retry-After", "60");
      res.status(error.status).json({ error: error.code });
    } else if (error.type === "entity.too.large")
      res.status(413).json({ error: "body_too_large" });
    else if (error.type === "entity.parse.failed")
      res.status(400).json({ error: "invalid_json" });
    else {
      console.error("Import request failed");
      res.status(500).json({ error: "internal_error" });
    }
  };
  app.use(errors);
  return app;
}
