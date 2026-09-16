import { getClickHouse, getPostgres } from "../src/server/db";
import { closeWorkersRuntime, createWorkersRuntime, runWorkersRuntime, runtimeEnvironment } from "../src/server/runtime";

type SafeError = { name: string; code?: string; message: string; detail?: string; cause?: SafeError };

function safeError(error: unknown, depth = 0): SafeError {
  const value = error && typeof error === "object" ? error as Record<string, unknown> : {};
  const source = typeof value.message === "string" ? value.message : "";
  // Classify private error text without returning it, URLs, stacks, headers,
  // queries, binding values or arbitrary driver error properties.
  const categories: [RegExp, string][] = [
    [/not configured/i, "Required runtime configuration is missing."],
    [/authentication|password|unauthorized|access denied/i, "Database authentication or authorization failed."],
    [/certificate|tls|ssl/i, "TLS or certificate validation failed."],
    [/timeout|timed out|deadline/i, "The database request timed out."],
    [/dns|enotfound|getaddrinfo/i, "Hostname resolution failed."],
    [/fetch failed|network|connection|socket|econn/i, "A network or connection request failed."],
    [/not implemented|not supported|unsupported/i, "The runtime does not support a required operation."],
    [/undefined|not a function|not defined/i, "A required runtime API or value is unavailable."],
    [/json|parse|unexpected token/i, "The response could not be parsed."],
    [/permission|forbidden/i, "The operation was forbidden."],
    [/database.*not exist|unknown database/i, "The configured database does not exist."],
    [/cannot.*read|cannot.*convert/i, "The client could not read or convert a runtime value."],
  ];
  const names = ["Error", "TypeError", "RangeError", "ReferenceError", "SyntaxError", "AbortError", "TimeoutError", "ClickHouseError", "DatabaseError"];
  const codes = ["ECONNREFUSED", "ECONNRESET", "ETIMEDOUT", "ENOTFOUND", "EAI_AGAIN", "ENETUNREACH", "EHOSTUNREACH", "UND_ERR_CONNECT_TIMEOUT", "CERT_HAS_EXPIRED", "ERR_TLS_CERT_ALTNAME_INVALID"];
  const code = String(value.code ?? "");
  const result: SafeError = {
    name: typeof value.name === "string" && names.includes(value.name) ? value.name : "Error",
    message: categories.find(([pattern]) => pattern.test(source))?.[1] ?? "Database runtime operation failed; private error details omitted.",
  };
  if (codes.includes(code) || /^\d{1,5}$/.test(code)) result.code = code;
  if (value.cause && depth < 2) result.cause = safeError(value.cause, depth + 1);
  // This diagnostic issues only SELECT 1. Redact all runtime values and network
  // addresses before returning the bounded driver diagnostic.
  let detail = source;
  for (const key of ["CLICKHOUSE_URL", "CLICKHOUSE_USERNAME", "CLICKHOUSE_PASSWORD", "CLICKHOUSE_DATABASE", "CLICKHOUSE_CDC_DATABASE", "CLERK_SECRET_KEY"]) {
    const secret = runtimeEnvironment(key);
    if (secret) detail = detail.replaceAll(secret, "[redacted]");
  }
  result.detail = detail.replace(/https?:\/\/\S+/g, "[url]").replace(/[\w.-]+\.clickhouse\.cloud/gi, "[host]").slice(0, 500);
  return result;
}

export default {
  async fetch(request, env) {
    if (new URL(request.url).searchParams.get("port") === "443") {
      const url = new URL(env.CLICKHOUSE_URL);
      url.port = "443";
      env = { ...env, CLICKHOUSE_URL: url.toString() };
    }
    const runtime = createWorkersRuntime(env);
    return runWorkersRuntime(runtime, async () => {
      const stages: { stage: string; ok: boolean; error?: SafeError }[] = [];
      try {
        try {
          await getPostgres().query("SELECT 1 AS ok");
          stages.push({ stage: "postgres", ok: true });
        } catch (error) { stages.push({ stage: "postgres", ok: false, error: safeError(error) }); }
        try {
          const result = await getClickHouse().query({ query: "SELECT 1 AS ok", format: "JSONEachRow" });
          await result.json();
          stages.push({ stage: "clickhouse", ok: true });
        } catch (error) { stages.push({ stage: "clickhouse", ok: false, error: safeError(error) }); }
      } finally {
        try {
          await closeWorkersRuntime(runtime);
          stages.push({ stage: "close", ok: true });
        } catch (error) { stages.push({ stage: "close", ok: false, error: safeError(error) }); }
      }
      return Response.json({ stages }, { status: stages.every((stage) => stage.ok) ? 200 : 503, headers: { "Cache-Control": "no-store" } });
    });
  },
} satisfies ExportedHandler<Env>;
