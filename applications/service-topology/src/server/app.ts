import { Elysia, t } from "elysia";
import type { Database } from "./database";
import { graphProblem, saveSchema } from "./graph";
import { readGraph, saveGraph, StaleRevision } from "./repository";
import { allowedRequest } from "./origin";
export const createApi = (db: Database) =>
  new Elysia({ prefix: "/api" })
    .onRequest(({ request, status }) => {
      if (!allowedRequest(request))
        return status(403, { message: "Use the configured local app origin." });
    })
    .get(
      "/graphs/:id",
      async ({ params, status }) => {
        const graph = await readGraph(db, params.id);
        return graph ?? status(404, { message: "Map not found." });
      },
      { params: t.Object({ id: t.String({ format: "uuid" }) }) },
    )
    .put(
      "/graphs/:id",
      async ({ params, body, status }) => {
        const problem = graphProblem(body.document);
        if (problem) return status(400, { message: problem });
        try {
          return await saveGraph(
            db,
            params.id,
            body.baseRevision,
            body.document,
          );
        } catch (error) {
          if (error instanceof StaleRevision)
            return status(409, { message: error.message });
          console.error("Graph save failed.");
          return status(500, {
            message: "Save failed. Your draft is still available.",
          });
        }
      },
      {
        params: t.Object({ id: t.String({ format: "uuid" }) }),
        body: saveSchema,
      },
    )
    .onError(({ code, status }) => {
      if (code === "VALIDATION")
        return status(422, {
          message:
            "The graph format is invalid. Check names, coordinates and size limits.",
        });
      console.error("API request failed.");
      return status(500, { message: "The map could not be loaded." });
    });
export type App = ReturnType<typeof createApi>;
