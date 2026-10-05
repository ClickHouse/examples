const protocol = new Set([
  "offset",
  "handle",
  "live",
  "cursor",
  "expired_handle",
  "cache-buster",
  "log",
]);
const shapes = {
  tasks: {
    table: "planning.tasks",
    columns: "id,board_id,project_id,title,status,priority,revision",
  },
  projects: { table: "planning.projects", columns: "id,board_id,name,color" },
} as const;
export function shapeUrl(
  requestUrl: string,
  kind: string,
  engine: string,
  secret: string,
) {
  if (!Object.hasOwn(shapes, kind)) throw new Error("Unknown shape");
  const source = new URL(requestUrl);
  const target = new URL("/v1/shape", engine);
  for (const [key, value] of source.searchParams) {
    if (
      (key === "log" && value !== "full") ||
      !protocol.has(key) ||
      source.searchParams.getAll(key).length !== 1
    )
      throw new Error("Unsupported shape parameter");
    target.searchParams.set(key, value);
  }
  const shape = shapes[kind as keyof typeof shapes];
  target.searchParams.set("table", shape.table);
  target.searchParams.set("columns", shape.columns);
  target.searchParams.set("where", "board_id = $1");
  target.searchParams.set("params[1]", "studio");
  target.searchParams.set("secret", secret);
  return target;
}
