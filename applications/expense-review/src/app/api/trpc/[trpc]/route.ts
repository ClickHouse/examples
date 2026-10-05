import { fetchRequestHandler } from "@trpc/server/adapters/fetch";
import { appRouter } from "@/server/router";
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
const handler = (req: Request) => {
  const origin = process.env.APP_ORIGIN ?? "http://127.0.0.1:4332";
  if (req.headers.get("host") !== new URL(origin).host)
    return Response.json({ message: "Invalid host." }, { status: 403 });
  if (
    req.method !== "GET" &&
    (req.headers.get("origin") !== origin ||
      req.headers.get("x-expense-review") !== "1")
  )
    return Response.json(
      { message: "Use the local same-origin review client." },
      { status: 403 },
    );
  return fetchRequestHandler({
    endpoint: "/api/trpc",
    req,
    router: appRouter,
    createContext: () => ({}),
    responseMeta: () => ({ headers: { "Cache-Control": "no-store" } }),
  });
};
export { handler as GET, handler as POST };
