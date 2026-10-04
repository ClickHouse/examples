import { t } from "elysia";
import type { GraphDocument } from "../shared/types";
export const graphSchema = t.Object({
  nodes: t.Array(
    t.Object({
      id: t.String({ format: "uuid" }),
      type: t.Literal("service"),
      position: t.Object({
        x: t.Number({ minimum: -100000, maximum: 100000 }),
        y: t.Number({ minimum: -100000, maximum: 100000 }),
      }),
      data: t.Object({
        label: t.String({ minLength: 1, maxLength: 60 }),
        kind: t.Union([
          t.Literal("web"),
          t.Literal("api"),
          t.Literal("worker"),
          t.Literal("database"),
        ]),
      }),
    }),
    { maxItems: 100 },
  ),
  edges: t.Array(
    t.Object({
      id: t.String({ format: "uuid" }),
      source: t.String({ format: "uuid" }),
      target: t.String({ format: "uuid" }),
    }),
    { maxItems: 200 },
  ),
});
export const saveSchema = t.Object({
  baseRevision: t.Integer({ minimum: 1, maximum: 2147483646 }),
  document: graphSchema,
});
export function graphProblem(document: GraphDocument): string | undefined {
  const ids = new Set(document.nodes.map((n) => n.id));
  if (ids.size !== document.nodes.length) return "Service IDs must be unique.";
  if (document.nodes.some((n) => !n.data.label.trim()))
    return "Service names cannot be blank.";
  if (
    document.nodes.some(
      (n) => !Number.isFinite(n.position.x) || !Number.isFinite(n.position.y),
    )
  )
    return "Coordinates must be finite.";
  const edges = new Set<string>();
  const pairs = new Set<string>();
  for (const edge of document.edges) {
    if (edges.has(edge.id)) return "Connection IDs must be unique.";
    if (!ids.has(edge.source) || !ids.has(edge.target))
      return "Connections must reference existing services.";
    if (edge.source === edge.target)
      return "A service cannot connect to itself.";
    const pair = edge.source + ":" + edge.target;
    if (pairs.has(pair))
      return "Only one connection in each direction is allowed.";
    pairs.add(pair);
    edges.add(edge.id);
  }
}
