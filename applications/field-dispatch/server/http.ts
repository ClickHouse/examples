import {
  createServer,
  type IncomingMessage,
  type ServerResponse,
} from "node:http";
import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import { resolve, sep, extname } from "node:path";
import { z } from "zod";
import {
  bootstrap,
  viewportJobs,
  assign,
  saveMap,
  DispatchError,
} from "./dispatch";

export function parseRange(value: string, size: number) {
  const match = /^bytes=(\d+)-(\d*)$/.exec(value);
  if (!match) throw new DispatchError("Use one forward byte range.", 416);
  const start = Number(match[1]);
  const end = match[2] ? Math.min(Number(match[2]), size - 1) : size - 1;
  if (
    !Number.isSafeInteger(start) ||
    !Number.isSafeInteger(end) ||
    start > end ||
    start >= size
  )
    throw new DispatchError("Byte range is outside the archive.", 416);
  return { start, end };
}
function json(response: ServerResponse, status: number, value: unknown) {
  response.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
  });
  response.end(JSON.stringify(value));
}
async function body(request: IncomingMessage) {
  if (request.headers["content-type"]?.split(";")[0] !== "application/json")
    throw new DispatchError("Send a JSON request body.", 415);
  const chunks: Buffer[] = [];
  let bytes = 0;
  for await (const chunk of request) {
    bytes += chunk.length;
    if (bytes > 8192)
      throw new DispatchError("Request body is too large.", 413);
    chunks.push(chunk);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    throw new DispatchError("Request body is not valid JSON.");
  }
}
async function staticFile(
  request: IncomingMessage,
  response: ServerResponse,
  pathname: string,
) {
  const archive = pathname === "/maintenance-town.pmtiles";
  const root = resolve(archive ? "public" : "dist");
  let path = resolve(root, pathname === "/" ? "index.html" : `.${pathname}`);
  if (!path.startsWith(root + sep))
    throw new DispatchError("File not found.", 404);
  let info;
  try {
    info = await stat(path);
  } catch {
    throw new DispatchError("File not found.", 404);
  }
  if (!info.isFile()) throw new DispatchError("File not found.", 404);
  const mime: Record<string, string> = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript",
    ".mjs": "text/javascript",
    ".css": "text/css",
    ".svg": "image/svg+xml",
    ".pmtiles": "application/octet-stream",
  };
  const headers: Record<string, string | number> = {
    "content-type": mime[extname(path)] ?? "application/octet-stream",
    "cache-control": archive ? "public, max-age=3600" : "no-cache",
    "content-length": info.size,
  };
  if (archive) headers["accept-ranges"] = "bytes";
  if (archive && request.headers.range) {
    const range = parseRange(request.headers.range, info.size);
    headers["content-range"] = `bytes ${range.start}-${range.end}/${info.size}`;
    headers["content-length"] = range.end - range.start + 1;
    response.writeHead(206, headers);
    if (request.method === "HEAD") response.end();
    else createReadStream(path, range).pipe(response);
  } else {
    response.writeHead(200, headers);
    if (request.method === "HEAD") response.end();
    else createReadStream(path).pipe(response);
  }
}
export function createApplication() {
  return createServer((request, response) => {
    void (async () => {
      const origin = process.env.APP_ORIGIN;
      if (
        !origin ||
        !["127.0.0.1", "localhost", "[::1]"].includes(new URL(origin).hostname)
      )
        throw new DispatchError("Configure a loopback APP_ORIGIN.", 503);
      if (
        request.headers.host !== new URL(origin).host ||
        (!["GET", "HEAD"].includes(request.method ?? "") &&
          request.headers.origin !== origin)
      )
        throw new DispatchError("Use the configured dispatch address.", 403);
      const url = new URL(request.url ?? "/", origin);
      if (request.method === "GET" && url.pathname === "/api/bootstrap")
        return json(response, 200, await bootstrap());
      if (request.method === "GET" && url.pathname === "/api/jobs")
        return json(
          response,
          200,
          await viewportJobs(Object.fromEntries(url.searchParams)),
        );
      if (request.method === "POST" && url.pathname === "/api/assign")
        return json(response, 200, await assign(await body(request)));
      if (request.method === "POST" && url.pathname === "/api/map")
        return json(response, 200, await saveMap(await body(request)));
      if (url.pathname.startsWith("/api/"))
        throw new DispatchError("API route not found.", 404);
      if (!["GET", "HEAD"].includes(request.method ?? ""))
        throw new DispatchError("Method not allowed.", 405);
      await staticFile(request, response, url.pathname);
    })().catch((error) => {
      if (error instanceof z.ZodError)
        return json(response, 400, {
          error: "Use valid coordinates, identifiers and revisions.",
        });
      if (error instanceof DispatchError)
        return json(response, error.status, { error: error.message });
      console.error(
        "Dispatch request failed.",
        error.code ?? error.constructor.name,
      );
      json(response, 503, {
        error: "Request failed. Check the database connection.",
      });
    });
  });
}
