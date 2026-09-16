import { createFileRoute } from "@tanstack/react-router";

async function resolve(slug: string, request: Request, head = false) {
  try {
    const { resolveRedirect } = await import("../server/service");
    const result = await resolveRedirect(
      slug,
      {
        referrer: request.headers.get("referer"),
        userAgent: request.headers.get("user-agent") || "",
      },
      !head,
      new URL(request.url).hostname,
    );
    const headers = {
      "Cache-Control": "no-store",
      "X-Robots-Tag": "noindex",
      "Referrer-Policy": "no-referrer",
    };
    if (result.status === 302)
      return new Response(null, {
        status: 302,
        headers: { ...headers, Location: result.location },
      });
    return new Response(
      head
        ? null
        : result.status === 410
          ? "This link has been disabled."
          : "This short link does not exist.",
      { status: result.status, headers },
    );
  } catch {
    return new Response(
      head ? null : "This link is temporarily unavailable. Please try again.",
      {
        status: 503,
        headers: { "Cache-Control": "no-store", "Retry-After": "30" },
      },
    );
  }
}
export const Route = createFileRoute("/r/$slug")({
  server: {
    handlers: {
      GET: ({ params, request }) => resolve(params.slug, request),
      HEAD: ({ params, request }) => resolve(params.slug, request, true),
    },
  },
});
