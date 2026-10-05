import { test, expect } from "bun:test";
import { shapeUrl } from "../src/server/proxy";
test("protocol advances preserve fixed board shape; arbitrary filters never reach Electric", () => {
  const u = shapeUrl(
    "http://localhost/api/shapes/tasks?offset=-1&handle=known",
    "tasks",
    "http://127.0.0.1:3005",
    "server-secret",
  );
  expect(u.searchParams.get("where")).toBe("board_id = $1");
  expect(u.searchParams.get("params[1]")).toBe("studio");
  expect(u.searchParams.get("offset")).toBe("-1");
  for (const param of [
    "table=pg_authid",
    "where=true",
    "columns=*",
    "params[1]=private-lab",
    "secret=other",
    "subset__where=true",
    "offset=-1&offset=9",
  ])
    expect(() =>
      shapeUrl(
        `http://localhost/api/shapes/tasks?${param}`,
        "tasks",
        "http://127.0.0.1:3005",
        "secret",
      ),
    ).toThrow();
  expect(() =>
    shapeUrl("http://localhost/", "unknown", "http://localhost/", "secret"),
  ).toThrow();
  for (const name of ["__proto__", "constructor", "toString"])
    expect(() =>
      shapeUrl("http://localhost/", name, "http://localhost/", "secret"),
    ).toThrow();
});
import { createApp } from "../src/server/app";
import type { Database } from "../src/server/database";
import { updateTaskSchema } from "../src/shared";
test("local origin and UUID validation refuse requests before database access", async () => {
  const app = createApp(
    undefined as unknown as Database,
    "http://127.0.0.1:3000",
    "http://127.0.0.1:3005",
    "test-secret",
  );
  const foreign = await app.request(
    "http://127.0.0.1:3000/api/shapes/tasks?offset=-1",
    { headers: { Host: "127.0.0.1:3000", Origin: "https://foreign.invalid" } },
  );
  expect(foreign.status).toBe(403);
  const malformed = await app.request(
    "http://127.0.0.1:3000/api/tasks/------------------------------------",
    {
      method: "PATCH",
      headers: { Host: "127.0.0.1:3000", Origin: "http://127.0.0.1:3000" },
    },
  );
  expect(malformed.status).toBe(400);
  expect(
    updateTaskSchema.safeParse({
      revision: 2147483648,
      status: "todo",
      priority: "low",
    }).success,
  ).toBe(false);
});
