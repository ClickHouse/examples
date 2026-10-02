const MAX_BODY = 8192;
export default defineEventHandler(async (event) => {
  const path = event.path.split("?")[0]!;
  if (!path.startsWith("/api/")) return;
  setHeader(event, "Cache-Control", "no-store");
  if (["GET", "HEAD", "OPTIONS"].includes(event.method)) return;
  const config = useRuntimeConfig(event);
  const origin = getHeader(event, "origin");
  // Configured canonical origin, never a client-controlled Host/forwarded header.
  if (
    !config.appOrigin ||
    origin !== config.appOrigin ||
    getHeader(event, "sec-fetch-site") === "cross-site"
  )
    throw createError({
      statusCode: 403,
      statusMessage: "This request must come from the directory.",
    });
  if (event.method === "DELETE" && path === "/api/_auth/session") return;
  if (!(
    (event.method === "POST" && path === "/api/auth/login") ||
    (event.method === "PUT" && path.startsWith("/api/profiles/"))
  ))
    return;
  if (getHeader(event, "content-type")?.split(";")[0] !== "application/json")
    throw createError({ statusCode: 415, statusMessage: "Send JSON." });
  if (Number(getHeader(event, "content-length") || 0) > MAX_BODY)
    throw createError({
      statusCode: 413,
      statusMessage: "Request is too large.",
    });
  let length = 0;
  const chunks: Buffer[] = [];
  for await (const chunk of event.node.req) {
    const bytes = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    length += bytes.length;
    if (length > MAX_BODY)
      throw createError({
        statusCode: 413,
        statusMessage: "Request is too large.",
      });
    chunks.push(bytes);
  }
  try {
    event.context.directoryBody = JSON.parse(
      Buffer.concat(chunks).toString("utf8"),
    );
  } catch {
    throw createError({ statusCode: 400, statusMessage: "Invalid JSON." });
  }
});
