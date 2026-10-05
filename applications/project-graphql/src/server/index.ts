import {
  createServer,
  type IncomingMessage,
  type ServerResponse,
} from "node:http";
import { readFile } from "node:fs/promises";
import { resolve, extname } from "node:path";
import { grafast } from "postgraphile/grafast";
import { connectDatabase } from "./database.ts";
import { createGraphile, verifiedSessions } from "./preset.ts";
import { login, getSession, logout } from "./sessions.ts";
import { validateOperation } from "./limits.ts";
const origin = process.env.APP_ORIGIN ?? "http://127.0.0.1:3002";
const target = new URL(origin);
if (
  target.protocol !== "http:" ||
  target.hostname !== "127.0.0.1" ||
  target.pathname !== "/"
)
  throw new Error("APP_ORIGIN must be an HTTP loopback origin");
const pool = await connectDatabase();
const pgl = createGraphile(pool);
await pgl.getSchemaResult();
function json(res: ServerResponse, status: number, value: unknown) {
  res.writeHead(status, {
    "Content-Type": "application/json",
    "Cache-Control": "no-store",
  });
  res.end(JSON.stringify(value));
}
async function body(req: IncomingMessage) {
  let value = "";
  for await (const chunk of req) {
    value += chunk;
    if (Buffer.byteLength(value) > 16384)
      throw new Error("Request is too large");
  }
  return JSON.parse(value);
}
const server = createServer(async (req, res) => {
  try {
    if (
      req.headers.host !== target.host ||
      (req.headers.origin && req.headers.origin !== origin) ||
      (req.method === "POST" && req.headers.origin !== origin)
    ) {
      json(res, 403, { error: "Unexpected host or origin" });
      return;
    }
    const path = new URL(req.url ?? "/", origin).pathname;
    if (path === "/api/login" && req.method === "POST") {
      const value = await body(req);
      if (
        typeof value.email !== "string" ||
        typeof value.password !== "string" ||
        value.email.length > 120 ||
        value.password.length > 120
      ) {
        json(res, 400, { error: "Email and password required" });
        return;
      }
      const token = await login(pool, value.email, value.password);
      if (!token) {
        json(res, 401, { error: "Email or password did not match" });
        return;
      }
      res.setHeader(
        "Set-Cookie",
        `ground_session=${token}; HttpOnly; SameSite=Strict; Path=/; Max-Age=7200`,
      );
      json(res, 200, { ok: true });
      return;
    }
    if (path === "/api/logout" && req.method === "POST") {
      await logout(pool, req.headers.cookie);
      res.setHeader(
        "Set-Cookie",
        "ground_session=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0",
      );
      json(res, 200, { ok: true });
      return;
    }
    if (path === "/api/me" && req.method === "GET") {
      json(res, 200, { session: await getSession(pool, req.headers.cookie) });
      return;
    }
    if (path === "/graphql" && req.method === "POST") {
      const session = await getSession(pool, req.headers.cookie);
      if (!session) {
        json(res, 401, { errors: [{ message: "Sign in required" }] });
        return;
      }
      const value = await body(req);
      const variables = value.variables ?? {};
      if (typeof variables !== "object" || Array.isArray(variables))
        throw new Error("Variables must be an object");
      validateOperation(value.query, variables, value.operationName);
      verifiedSessions.set(req, session);
      const { schema, resolvedPreset } = await pgl.getSchemaResult();
      const result = await grafast({
        schema,
        resolvedPreset,
        requestContext: { node: { req, res } },
        source: value.query,
        variableValues: variables,
        operationName: value.operationName,
      });
      if (Symbol.asyncIterator in result)
        throw new Error("Streaming operations are not enabled");
      json(res, 200, {
        ...result,
        errors: result.errors?.map((error) => ({
          message:
            error.extensions?.code === "UNAUTHENTICATED"
              ? "Sign in required"
              : "The operation could not be completed",
          path: error.path,
        })),
      });
      return;
    }
    if (req.method !== "GET") {
      json(res, 404, { error: "Not found" });
      return;
    }
    const file = resolve("dist", path === "/" ? "index.html" : "." + path);
    if (!file.startsWith(resolve("dist") + "/")) {
      json(res, 404, { error: "Not found" });
      return;
    }
    try {
      const data = await readFile(file);
      res.writeHead(200, {
        "Content-Type":
          (
            {
              ".html": "text/html",
              ".js": "text/javascript",
              ".css": "text/css",
              ".png": "image/png",
            } as Record<string, string>
          )[extname(file)] ?? "application/octet-stream",
      });
      res.end(data);
    } catch {
      json(res, 404, { error: "Not found" });
    }
  } catch (error) {
    console.error(
      "Request failed",
      error instanceof Error ? error.name : "Unknown",
    );
    json(res, 400, { error: "Invalid or unsupported request" });
  }
});
server.listen(Number(target.port || 80), "127.0.0.1", () =>
  console.log(`Common Ground on ${origin}`),
);
for (const signal of ["SIGINT", "SIGTERM"] as const)
  process.on(signal, () => {
    server.close(async () => {
      await pgl.release();
      await pool.end();
      process.exit(0);
    });
  });
