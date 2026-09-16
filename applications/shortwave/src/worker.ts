import handler from "@tanstack/react-start/server-entry";
import { flushOutbox } from "./server/outbox";
import {
  closeWorkersRuntime,
  createWorkersRuntime,
  runWorkersRuntime,
  runtimeEnvironment,
} from "./server/runtime";

export default {
  async fetch(request, env, ctx) {
    const runtime = createWorkersRuntime(env);
    return runWorkersRuntime(runtime, async () => {
      try {
        const url = new URL(request.url);
        const customDomains = (runtimeEnvironment("PUBLIC_CUSTOM_DOMAINS") || "")
          .split(",").map((hostname) => hostname.trim().toLowerCase()).filter(Boolean);
        if (customDomains.includes(url.hostname.toLowerCase())) {
          const readable = request.method === "GET" || request.method === "HEAD";
          if (readable && url.pathname === "/") {
            return Response.redirect(runtimeEnvironment("APP_URL")!, 302);
          }
          if (!readable || !/^\/r\/[^/]+$/.test(url.pathname)) {
            return new Response("Not found", { status: 404 });
          }
        }

        const response = await handler.fetch(request);
        if (!response.body) {
          await closeWorkersRuntime(runtime);
          return response;
        }
        // SSR can continue loading while its body streams. Keep its scoped
        // connections alive through completion/cancellation, then release them.
        const { readable, writable } = new TransformStream();
        ctx.waitUntil((async () => {
          try {
            await response.body!.pipeTo(writable);
          } catch {
            // A disconnected browser cancels the stream. Do not log response data.
          } finally {
            await closeWorkersRuntime(runtime);
          }
        })());
        return new Response(readable, response);
      } catch {
        await closeWorkersRuntime(runtime);
        console.error(JSON.stringify({ event: "request_failed" }));
        return new Response("Internal server error", { status: 500 });
      }
    });
  },

  async scheduled(_event, env, _ctx) {
    const runtime = createWorkersRuntime(env);
    await runWorkersRuntime(runtime, async () => {
      try {
        // Bounded work per tick; SKIP LOCKED makes overlapping ticks safe.
        for (let batch = 0; batch < 5; batch++) {
          const result = await flushOutbox(500);
          if (result.failed || result.delivered < 500) break;
        }
      } finally {
        await closeWorkersRuntime(runtime);
      }
    });
  },
} satisfies ExportedHandler<Env>;
