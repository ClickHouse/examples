export function allowedRequest(
  request: Request,
  appOrigin = process.env.APP_ORIGIN || "http://127.0.0.1:3000",
) {
  const origin = new URL(appOrigin);
  if (
    origin.protocol !== "http:" ||
    origin.origin !== appOrigin ||
    !["127.0.0.1", "localhost", "[::1]"].includes(origin.hostname)
  )
    throw new Error(
      "APP_ORIGIN must be a loopback HTTP origin without a trailing slash.",
    );
  if (new URL(request.url).host !== origin.host) return false;
  return (
    request.method !== "PUT" || request.headers.get("origin") === appOrigin
  );
}
