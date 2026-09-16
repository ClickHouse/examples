// Optional diagnostic Worker. Deploy under a distinct name with no routes/cron.
// Its only database operations are SELECT 1 using application runtime drivers.
import { getClickHouse, getPostgres } from "../src/server/db";
import { closeWorkersRuntime, createWorkersRuntime, runWorkersRuntime } from "../src/server/runtime";

type DiagnosticEnv = Env & { DIAGNOSTIC_TOKEN: string };
type Stage = { stage: "postgres" | "clickhouse" | "close"; ok: boolean };

export default {
  async fetch(request: Request, env: DiagnosticEnv) {
    if (!env.DIAGNOSTIC_TOKEN || request.method !== "GET" ||
        request.headers.get("authorization") !== `Bearer ${env.DIAGNOSTIC_TOKEN}`) {
      return new Response("Unauthorized", { status: 401, headers: { "Cache-Control": "no-store" } });
    }
    const port = new URL(request.url).searchParams.get("port");
    if (port !== null && port !== "443") return new Response("Invalid port", { status: 400 });
    if (port === "443") {
      try {
        const url = new URL(env.CLICKHOUSE_URL);
        url.port = "443";
        env = { ...env, CLICKHOUSE_URL: url.toString() };
      } catch {
        return Response.json({ stages: [{ stage: "clickhouse", ok: false }] }, { status: 503 });
      }
    }
    const runtime = createWorkersRuntime(env);
    return runWorkersRuntime(runtime, async () => {
      const stages: Stage[] = [];
      try {
        try {
          await getPostgres().query("SELECT 1 AS ok");
          stages.push({ stage: "postgres", ok: true });
        } catch { stages.push({ stage: "postgres", ok: false }); }
        try {
          const result = await getClickHouse().query({ query: "SELECT 1 AS ok", format: "JSONEachRow" });
          await result.json();
          stages.push({ stage: "clickhouse", ok: true });
        } catch { stages.push({ stage: "clickhouse", ok: false }); }
      } finally {
        try {
          await closeWorkersRuntime(runtime);
          stages.push({ stage: "close", ok: true });
        } catch { stages.push({ stage: "close", ok: false }); }
      }
      return Response.json({ stages }, {
        status: stages.every(stage => stage.ok) ? 200 : 503,
        headers: { "Cache-Control": "no-store" },
      });
    });
  },
} satisfies ExportedHandler<DiagnosticEnv>;
