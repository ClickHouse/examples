import { defineMiddleware } from "astro:middleware";
export const onRequest = defineMiddleware(async ({ request }, next) => {
  const origin = process.env.APP_ORIGIN ?? "http://127.0.0.1:4321";
  const expected = new URL(origin);
  if (!["127.0.0.1", "[::1]", "localhost"].includes(expected.hostname))
    throw new Error("APP_ORIGIN must use loopback");
  if (request.headers.get("host") !== expected.host)
    return new Response("Invalid host", { status: 403 });
  if (
    !["GET", "HEAD"].includes(request.method) &&
    (request.headers.get("origin") !== origin ||
      request.headers.get("x-quote-catalogue") !== "1")
  ) {
    return new Response("Same-origin requests required", { status: 403 });
  }
  const response = await next();
  response.headers.set("Cache-Control", "no-store");
  return response;
});
